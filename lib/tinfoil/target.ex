defmodule Tinfoil.Target do
  @moduledoc """
  The core target matrix — the most valuable knowledge tinfoil encodes.

  Each target atom resolves to a full build specification including the
  GitHub Actions runner, Burrito target/cpu atoms, canonical triple used
  in archive names, and archive extension.

  ## Built-in targets

    * `:darwin_arm64`  — Apple Silicon macOS
    * `:darwin_x86_64` — Intel macOS
    * `:linux_x86_64`  — x86_64 Linux (musl)
    * `:linux_arm64`   — aarch64 Linux (musl)

  Triples follow the standard Rust-style convention (e.g.
  `aarch64-apple-darwin`) because that is what users expect in release
  asset names.

  ## Extending the matrix

  Projects can declare additional targets via the `:extra_targets` key
  in their `:tinfoil` config. Every function in this module that looks
  up a target accepts an optional `extras` map that is merged on top of
  the built-in matrix. Extras take precedence on name collision.
  """

  @type target :: atom()

  @type spec :: %{
          runner: String.t(),
          burrito_os: atom(),
          burrito_cpu: atom(),
          triple: String.t(),
          archive_ext: String.t(),
          os_family: atom()
        }

  @type extras :: %{atom() => spec()}

  @builtin %{
    darwin_arm64: %{
      runner: "macos-latest",
      burrito_os: :darwin,
      burrito_cpu: :aarch64,
      triple: "aarch64-apple-darwin",
      archive_ext: ".tar.gz",
      os_family: :darwin
    },
    darwin_x86_64: %{
      runner: "macos-15-intel",
      burrito_os: :darwin,
      burrito_cpu: :x86_64,
      triple: "x86_64-apple-darwin",
      archive_ext: ".tar.gz",
      os_family: :darwin
    },
    linux_x86_64: %{
      runner: "ubuntu-latest",
      burrito_os: :linux,
      burrito_cpu: :x86_64,
      triple: "x86_64-unknown-linux-musl",
      archive_ext: ".tar.gz",
      os_family: :linux
    },
    linux_arm64: %{
      # Cross-compiled from x86_64 via Zig (the same path Burrito uses for
      # Windows). ubuntu-24.04-arm is only available on paid GitHub plans,
      # so the free-tier friendly default wins. Paid users can flip the
      # runner back via :extra_targets if they want a native arm64 build.
      runner: "ubuntu-latest",
      burrito_os: :linux,
      burrito_cpu: :aarch64,
      triple: "aarch64-unknown-linux-musl",
      archive_ext: ".tar.gz",
      os_family: :linux
    },
    windows_x86_64: %{
      # Burrito cross-compiles the Windows .exe from Linux via Zig; a
      # native Windows runner is not needed and is slower anyway.
      runner: "ubuntu-latest",
      burrito_os: :windows,
      burrito_cpu: :x86_64,
      triple: "x86_64-pc-windows-msvc",
      archive_ext: ".zip",
      os_family: :windows
    }
  }

  @required_spec_keys [:runner, :burrito_os, :burrito_cpu, :triple, :archive_ext, :os_family]

  @doc "Return the list of all built-in target atoms."
  @spec builtin() :: [target()]
  def builtin, do: Map.keys(@builtin)

  @doc """
  Return the list of all known target atoms, including any extras.
  """
  @spec all(extras()) :: [target()]
  def all(extras \\ %{}) do
    matrix(extras) |> Map.keys()
  end

  @doc """
  Return the full spec for a target atom, or `nil` if unknown.
  """
  @spec spec(target(), extras()) :: spec() | nil
  def spec(target, extras \\ %{}) when is_atom(target) do
    Map.get(matrix(extras), target)
  end

  @doc """
  Return the full spec for a target atom, raising on unknown targets.
  """
  @spec spec!(target(), extras()) :: spec()
  def spec!(target, extras \\ %{}) when is_atom(target) do
    m = matrix(extras)

    case Map.fetch(m, target) do
      {:ok, spec} ->
        spec

      :error ->
        raise ArgumentError,
              "unknown tinfoil target: #{inspect(target)}. " <>
                "Valid targets: #{inspect(Map.keys(m))}"
    end
  end

  @doc "Return the canonical Rust-style triple for a target."
  @spec triple(target(), extras()) :: String.t()
  def triple(target, extras \\ %{}), do: spec!(target, extras).triple

  @doc "Return the GitHub Actions runner label for a target."
  @spec runner(target(), extras()) :: String.t()
  def runner(target, extras \\ %{}), do: spec!(target, extras).runner

  @doc "Return the Burrito `[os: ..., cpu: ...]` keyword list for a target."
  @spec burrito_target(target(), extras()) :: keyword()
  def burrito_target(target, extras \\ %{}) do
    s = spec!(target, extras)
    [os: s.burrito_os, cpu: s.burrito_cpu]
  end

  @doc """
  Validate a list of target atoms against the built-in matrix plus the
  supplied extras. Returns `:ok` or `{:error, {:unknown_targets, [atom()]}}`.
  """
  @spec validate([target()], extras()) :: :ok | {:error, {:unknown_targets, [atom()]}}
  def validate(targets, extras \\ %{}) when is_list(targets) do
    m = matrix(extras)
    unknown = Enum.reject(targets, &Map.has_key?(m, &1))

    case unknown do
      [] -> :ok
      bad -> {:error, {:unknown_targets, bad}}
    end
  end

  @doc """
  Validate an `:extra_targets` map from user config. Each entry must be
  an atom key mapped to a spec map with every required key present.
  """
  @spec validate_extras(term()) :: {:ok, extras()} | {:error, term()}
  def validate_extras(nil), do: {:ok, %{}}
  def validate_extras(map) when map_size(map) == 0 and is_map(map), do: {:ok, %{}}

  def validate_extras(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {name, spec}, {:ok, acc} ->
      cond do
        not is_atom(name) ->
          {:halt, {:error, {:extra_target_name_not_atom, name}}}

        Map.has_key?(@builtin, name) ->
          {:halt, {:error, {:extra_target_shadows_builtin, name}}}

        not is_map(spec) ->
          {:halt, {:error, {:extra_target_spec_not_map, name}}}

        (missing = @required_spec_keys -- Map.keys(spec)) != [] ->
          {:halt, {:error, {:extra_target_missing_keys, name, missing}}}

        true ->
          {:cont, {:ok, Map.put(acc, name, Map.take(spec, @required_spec_keys))}}
      end
    end)
  end

  def validate_extras(other), do: {:error, {:extra_targets_not_map, other}}

  defp matrix(extras) when is_map(extras), do: Map.merge(@builtin, extras)
end
