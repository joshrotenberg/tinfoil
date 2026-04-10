defmodule Tinfoil.Target do
  @moduledoc """
  The core target matrix — the most valuable knowledge tinfoil encodes.

  Each target atom resolves to a full build specification including the
  GitHub Actions runner, Burrito target/cpu atoms, canonical triple used
  in archive names, and archive extension.

  ## Supported targets

    * `:darwin_arm64`  — Apple Silicon macOS
    * `:darwin_x86_64` — Intel macOS
    * `:linux_x86_64`  — x86_64 Linux (musl)
    * `:linux_arm64`   — aarch64 Linux (musl)

  Triples follow the standard Rust-style convention (e.g.
  `aarch64-apple-darwin`) because that is what users expect in release
  asset names.
  """

  @type target :: :darwin_arm64 | :darwin_x86_64 | :linux_x86_64 | :linux_arm64

  @type spec :: %{
          runner: String.t(),
          burrito_os: atom(),
          burrito_cpu: atom(),
          triple: String.t(),
          archive_ext: String.t(),
          os_family: :darwin | :linux
        }

  @matrix %{
    darwin_arm64: %{
      runner: "macos-latest",
      burrito_os: :darwin,
      burrito_cpu: :aarch64,
      triple: "aarch64-apple-darwin",
      archive_ext: ".tar.gz",
      os_family: :darwin
    },
    darwin_x86_64: %{
      runner: "macos-13",
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
      runner: "ubuntu-24.04-arm",
      burrito_os: :linux,
      burrito_cpu: :aarch64,
      triple: "aarch64-unknown-linux-musl",
      archive_ext: ".tar.gz",
      os_family: :linux
    }
  }

  @doc "Return the list of all known target atoms."
  @spec all() :: [target()]
  def all, do: Map.keys(@matrix)

  @doc """
  Return the full spec for a target atom, or `nil` if unknown.
  """
  @spec spec(target()) :: spec() | nil
  def spec(target) when is_atom(target), do: Map.get(@matrix, target)

  @doc """
  Return the full spec for a target atom, raising on unknown targets.
  """
  @spec spec!(target()) :: spec()
  def spec!(target) when is_atom(target) do
    case Map.fetch(@matrix, target) do
      {:ok, spec} ->
        spec

      :error ->
        raise ArgumentError,
              "unknown tinfoil target: #{inspect(target)}. " <>
                "Valid targets: #{inspect(all())}"
    end
  end

  @doc "Return the canonical Rust-style triple for a target."
  @spec triple(target()) :: String.t()
  def triple(target), do: spec!(target).triple

  @doc "Return the GitHub Actions runner label for a target."
  @spec runner(target()) :: String.t()
  def runner(target), do: spec!(target).runner

  @doc "Return the Burrito `[os: ..., cpu: ...]` keyword list for a target."
  @spec burrito_target(target()) :: keyword()
  def burrito_target(target) do
    spec = spec!(target)
    [os: spec.burrito_os, cpu: spec.burrito_cpu]
  end

  @doc """
  Validate a list of target atoms. Returns `:ok` or
  `{:error, {:unknown_targets, [atom()]}}`.
  """
  @spec validate([target()]) :: :ok | {:error, {:unknown_targets, [atom()]}}
  def validate(targets) when is_list(targets) do
    unknown = Enum.reject(targets, &Map.has_key?(@matrix, &1))

    case unknown do
      [] -> :ok
      bad -> {:error, {:unknown_targets, bad}}
    end
  end
end
