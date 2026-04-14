defmodule Tinfoil.Config do
  @moduledoc """
  Schema, defaults, and validation for the `:tinfoil` key in `mix.exs`.

  The user's configuration lives in `project/0`:

      def project do
        [
          app: :my_cli,
          version: "0.1.0",
          tinfoil: [
            targets: [:darwin_arm64, :linux_x86_64]
          ]
        ]
      end

  Everything except `:targets` has a default. `Tinfoil.Config.load/1`
  returns a fully-resolved `%Tinfoil.Config{}` struct, merging user
  values with defaults and inferring values from the surrounding mix
  project where possible.
  """

  alias Tinfoil.{Burrito, Target}

  @enforce_keys [:app, :version, :targets, :burrito_names]
  defstruct [
    :app,
    :version,
    :description,
    :homepage_url,
    :license,
    :targets,
    :burrito_names,
    archive_name: "{app}-{version}-{target}",
    archive_format: :tar_gz,
    github: %{repo: nil, draft: false},
    homebrew: %{enabled: false, tap: nil, formula_name: nil},
    installer: %{enabled: false, install_dir: "~/.local/bin"},
    checksums: :sha256,
    prerelease_pattern: nil,
    extra_targets: %{},
    ci: %{
      provider: :github_actions,
      elixir_version: "1.19",
      otp_version: "28",
      zig_version: "0.15.2"
    }
  ]

  @type t :: %__MODULE__{
          app: atom(),
          version: String.t(),
          description: String.t() | nil,
          homepage_url: String.t() | nil,
          license: String.t() | nil,
          targets: [Target.target()],
          burrito_names: %{Target.target() => atom()},
          archive_name: String.t(),
          archive_format: :tar_gz | :zip,
          github: map(),
          homebrew: map(),
          installer: map(),
          checksums: :sha256,
          prerelease_pattern: Regex.t(),
          extra_targets: Target.extras(),
          ci: map()
        }

  @doc """
  Load and resolve the config from a mix project keyword list.

  Accepts the return value of `Mix.Project.config/0` (or an equivalent
  keyword list in tests). Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(project) when is_list(project) do
    app = Keyword.fetch!(project, :app)

    with {:ok, tinfoil} <- fetch_tinfoil(project),
         {:ok, extra_targets} <- Target.validate_extras(Keyword.get(tinfoil, :extra_targets, %{})),
         {:ok, targets} <- fetch_targets(tinfoil),
         :ok <- Target.validate(targets, extra_targets),
         {:ok, archive_name} <- fetch_archive_name(tinfoil),
         {:ok, archive_format} <- fetch_archive_format(tinfoil),
         {:ok, prerelease_pattern} <- fetch_prerelease_pattern(tinfoil),
         {:ok, homebrew} <- fetch_homebrew(tinfoil, project),
         {:ok, burrito_targets} <- Burrito.extract_targets(project, app),
         {:ok, burrito_names} <- Burrito.resolve_all(targets, burrito_targets, extra_targets) do
      config = %__MODULE__{
        app: app,
        version: Keyword.fetch!(project, :version),
        description: Keyword.get(project, :description),
        homepage_url: Keyword.get(project, :homepage_url),
        license: extract_license(project),
        targets: targets,
        burrito_names: burrito_names,
        archive_name: archive_name,
        archive_format: archive_format,
        github: merge_github(Keyword.get(tinfoil, :github, [])),
        homebrew: homebrew,
        installer: merge_installer(Keyword.get(tinfoil, :installer, [])),
        checksums: Keyword.get(tinfoil, :checksums, :sha256),
        prerelease_pattern: prerelease_pattern,
        extra_targets: extra_targets,
        ci: merge_ci(Keyword.get(tinfoil, :ci, []), project)
      }

      {:ok, config}
    end
  end

  @doc "Load the config, raising on any error."
  @spec load!(keyword()) :: t()
  def load!(project) do
    case load(project) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, format_error(reason)
    end
  end

  @doc """
  Render an archive file name (without extension) for the given target.

  Uses `:archive_name` as a template. Available interpolations: `{app}`,
  `{version}`, `{target}` (the canonical triple).
  """
  @spec archive_basename(t(), Target.target()) :: String.t()
  def archive_basename(%__MODULE__{} = config, target) do
    triple = Target.triple(target, config.extra_targets)

    config.archive_name
    |> String.replace("{app}", to_string(config.app))
    |> String.replace("{version}", config.version)
    |> String.replace("{target}", triple)
  end

  @doc "Return the archive extension (including the leading dot)."
  @spec archive_extension(t()) :: String.t()
  def archive_extension(%__MODULE__{archive_format: :tar_gz}), do: ".tar.gz"
  def archive_extension(%__MODULE__{archive_format: :zip}), do: ".zip"

  @doc """
  Full archive file name for a target, including extension.
  """
  @spec archive_filename(t(), Target.target()) :: String.t()
  def archive_filename(%__MODULE__{} = config, target) do
    archive_basename(config, target) <> archive_extension(config)
  end

  ## ───────────────────── internals ─────────────────────

  defp fetch_tinfoil(project) do
    case Keyword.fetch(project, :tinfoil) do
      {:ok, tinfoil} when is_list(tinfoil) -> {:ok, tinfoil}
      {:ok, _} -> {:error, :tinfoil_config_not_keyword_list}
      :error -> {:error, :missing_tinfoil_config}
    end
  end

  defp fetch_targets(tinfoil) do
    case Keyword.fetch(tinfoil, :targets) do
      {:ok, [_ | _] = targets} -> {:ok, targets}
      {:ok, []} -> {:error, :empty_targets}
      {:ok, _} -> {:error, :targets_not_a_list}
      :error -> {:error, :missing_targets}
    end
  end

  defp fetch_archive_name(tinfoil) do
    name = Keyword.get(tinfoil, :archive_name, "{app}-{version}-{target}")

    cond do
      not is_binary(name) ->
        {:error, :archive_name_not_string}

      not String.contains?(name, "{target}") ->
        {:error, {:archive_name_missing_target_token, name}}

      true ->
        {:ok, name}
    end
  end

  @valid_archive_formats [:tar_gz, :zip]

  defp fetch_archive_format(tinfoil) do
    format = Keyword.get(tinfoil, :archive_format, :tar_gz)

    if format in @valid_archive_formats do
      {:ok, format}
    else
      {:error, {:invalid_archive_format, format}}
    end
  end

  @default_prerelease_pattern ~r/-(rc|beta|alpha)(\.|$)/

  defp fetch_prerelease_pattern(tinfoil) do
    case Keyword.fetch(tinfoil, :prerelease_pattern) do
      :error -> {:ok, @default_prerelease_pattern}
      {:ok, %Regex{} = r} -> {:ok, r}
      {:ok, other} -> {:error, {:invalid_prerelease_pattern, other}}
    end
  end

  defp fetch_homebrew(tinfoil, project) do
    merged = merge_homebrew(Keyword.get(tinfoil, :homebrew, []), project)

    cond do
      not merged.enabled ->
        {:ok, merged}

      is_nil(merged.tap) or merged.tap == "" ->
        {:error, :homebrew_enabled_without_tap}

      not valid_tap_format?(merged.tap) ->
        {:error, {:invalid_homebrew_tap, merged.tap}}

      not valid_formula_name?(merged.formula_name) ->
        {:error, {:invalid_formula_name, merged.formula_name}}

      true ->
        {:ok, merged}
    end
  end

  # Tap must be "owner/repo" format (typically owner/homebrew-name).
  defp valid_tap_format?(tap) when is_binary(tap) do
    Regex.match?(~r|^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$|, tap)
  end

  defp valid_tap_format?(_), do: false

  # Formula names must be valid Ruby identifiers (lowercase, underscores, hyphens).
  defp valid_formula_name?(name) when is_binary(name) do
    Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name)
  end

  defp valid_formula_name?(_), do: false

  defp extract_license(project) do
    case get_in(project, [:package, :licenses]) do
      [first | _] -> first
      _ -> nil
    end
  end

  defp merge_github(user) do
    defaults = %{repo: nil, draft: false}

    defaults
    |> Map.merge(Map.new(user))
    |> Map.update!(:repo, fn
      nil -> infer_github_repo()
      repo -> repo
    end)
  end

  defp merge_homebrew(user, project) do
    defaults = %{enabled: false, tap: nil, formula_name: nil}
    merged = Map.merge(defaults, Map.new(user))

    formula_name =
      merged.formula_name ||
        project
        |> Keyword.fetch!(:app)
        |> to_string()

    %{merged | formula_name: formula_name}
  end

  defp merge_installer(user) do
    defaults = %{enabled: false, install_dir: "~/.local/bin"}
    Map.merge(defaults, Map.new(user))
  end

  defp merge_ci(user, project) do
    defaults = %{
      provider: :github_actions,
      elixir_version: infer_elixir_version(project),
      otp_version: infer_otp_version(),
      zig_version: infer_zig_version()
    }

    Map.merge(defaults, Map.new(user))
  end

  # Parse the user's mix.exs :elixir requirement (e.g. "~> 1.19", ">= 1.15.0")
  # into a "MAJOR.MINOR" string suitable for erlef/setup-beam. Falls back to
  # the current latest stable when the requirement can't be parsed.
  @fallback_elixir_version "1.19"

  defp infer_elixir_version(project) do
    case Keyword.get(project, :elixir) do
      req when is_binary(req) ->
        case Regex.run(~r/(\d+\.\d+)/, req) do
          [_, version] -> version
          _ -> @fallback_elixir_version
        end

      _ ->
        @fallback_elixir_version
    end
  end

  # Try to read Burrito's required Zig version via Burrito.get_versions/0.
  # Falls back to a hardcoded default when Burrito isn't loaded (e.g. in
  # tinfoil's own test suite).
  @fallback_zig_version "0.15.2"

  defp infer_zig_version do
    if Code.ensure_loaded?(Burrito) and function_exported?(Burrito, :get_versions, 0) do
      # Burrito is not a dep of tinfoil; apply/3 avoids a compile-time warning.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Burrito, :get_versions, []).zig |> Version.to_string()
    else
      @fallback_zig_version
    end
  rescue
    _ -> @fallback_zig_version
  end

  # Read OTP major version from the running system. System.otp_release/0
  # returns a string like "28", which maps directly to erlef/setup-beam's
  # otp-version input.
  @fallback_otp_version "28"

  defp infer_otp_version do
    case System.otp_release() do
      rel when is_binary(rel) and rel != "" -> rel
      _ -> @fallback_otp_version
    end
  rescue
    _ -> @fallback_otp_version
  end

  @doc false
  def infer_github_repo do
    case System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> parse_git_remote()

      _ ->
        nil
    end
  rescue
    ErlangError -> nil
  end

  defp parse_git_remote("git@github.com:" <> rest) do
    rest |> String.trim_trailing(".git") |> String.trim_trailing("/")
  end

  defp parse_git_remote("https://github.com/" <> rest) do
    rest |> String.trim_trailing(".git") |> String.trim_trailing("/")
  end

  defp parse_git_remote("ssh://git@github.com/" <> rest) do
    rest |> String.trim_trailing(".git") |> String.trim_trailing("/")
  end

  defp parse_git_remote(_), do: nil

  defp format_error(:missing_tinfoil_config),
    do: "no :tinfoil key found in mix.exs project/0"

  defp format_error(:tinfoil_config_not_keyword_list),
    do: ":tinfoil config in mix.exs must be a keyword list"

  defp format_error(:missing_targets),
    do: ":tinfoil config must include a :targets list"

  defp format_error(:empty_targets),
    do: ":tinfoil :targets list is empty; specify at least one target"

  defp format_error(:targets_not_a_list),
    do: ":tinfoil :targets must be a list of target atoms"

  defp format_error({:unknown_targets, bad}) do
    "unknown tinfoil targets: #{inspect(bad)}. " <>
      "Valid targets: #{inspect(Target.builtin())} (plus any :extra_targets you declare)"
  end

  defp format_error(:archive_name_not_string),
    do: ":tinfoil :archive_name must be a string template"

  defp format_error({:archive_name_missing_target_token, name}),
    do:
      ":tinfoil :archive_name #{inspect(name)} is missing the `{target}` token. " <>
        "Without it every target produces the same filename and archives collide."

  defp format_error({:invalid_archive_format, format}),
    do:
      ":tinfoil :archive_format #{inspect(format)} is not supported. " <>
        "Valid formats: #{inspect(@valid_archive_formats)}"

  defp format_error(:homebrew_enabled_without_tap),
    do:
      ":tinfoil :homebrew is enabled but :tap is missing or empty. " <>
        "Set `homebrew: [enabled: true, tap: \"owner/homebrew-tap\"]` or disable homebrew."

  defp format_error({:invalid_homebrew_tap, tap}),
    do:
      ":tinfoil :homebrew :tap #{inspect(tap)} is not valid. " <>
        "Expected \"owner/repo\" format (e.g. \"owner/homebrew-tap\")."

  defp format_error({:invalid_formula_name, name}),
    do:
      ":tinfoil :homebrew :formula_name #{inspect(name)} is not a valid Homebrew formula name. " <>
        "Use lowercase letters, digits, hyphens, and underscores (e.g. \"my-cli\")."

  defp format_error(:release_opts_not_keyword_list),
    do: "the selected release's options block is not a keyword list"

  defp format_error(:missing_releases),
    do:
      "no :releases block found in mix.exs — tinfoil requires a Burrito " <>
        "release config. See https://github.com/burrito-elixir/burrito#usage"

  defp format_error(:releases_empty_or_invalid),
    do: ":releases must be a non-empty keyword list of release configurations"

  defp format_error(:missing_burrito_in_release),
    do:
      "the selected release has no :burrito key — add a " <>
        "burrito: [targets: [...]] block inside the release options"

  defp format_error(:burrito_not_keyword_list),
    do: ":burrito must be a keyword list"

  defp format_error(:missing_burrito_targets),
    do: ":burrito block has no :targets list"

  defp format_error(:burrito_targets_empty_or_invalid),
    do: ":burrito :targets must be a non-empty keyword list"

  defp format_error(:burrito_targets_malformed),
    do: ":burrito :targets entries must be `name: [os: atom, cpu: atom]`"

  defp format_error({:invalid_burrito_target, name}),
    do:
      "Burrito target #{inspect(name)} is missing :os or :cpu — " <>
        "each target must be `name: [os: atom, cpu: atom]`"

  defp format_error({:multiple_releases_no_match, names, app}),
    do:
      "multiple releases in mix.exs (#{inspect(names)}) but none named #{inspect(app)}. " <>
        "Either name a release after the app or keep a single release."

  defp format_error({:no_matching_burrito_target, target, spec}) do

    "tinfoil target #{inspect(target)} has no matching Burrito target " <>
      "(looking for [os: #{inspect(spec.burrito_os)}, cpu: #{inspect(spec.burrito_cpu)}]). " <>
      "Add a matching entry to your :burrito :targets in mix.exs."
  end

  defp format_error({:extra_targets_not_map, v}),
    do: ":tinfoil :extra_targets must be a map, got: #{inspect(v)}"

  defp format_error({:extra_target_name_not_atom, name}),
    do: ":tinfoil :extra_targets key #{inspect(name)} must be an atom"

  defp format_error({:extra_target_shadows_builtin, name}),
    do:
      ":tinfoil :extra_targets #{inspect(name)} collides with a built-in target. " <>
        "Pick a different name or remove it."

  defp format_error({:extra_target_spec_not_map, name}),
    do: ":tinfoil :extra_targets #{inspect(name)} spec must be a map"

  defp format_error({:extra_target_missing_keys, name, missing}),
    do:
      ":tinfoil :extra_targets #{inspect(name)} is missing required keys: #{inspect(missing)}. " <>
        "Each extra target needs :runner, :burrito_os, :burrito_cpu, :triple, :archive_ext, :os_family."

  defp format_error({:invalid_prerelease_pattern, value}),
    do:
      ":tinfoil :prerelease_pattern must be a Regex (e.g. ~r/-(rc|beta)/), got: #{inspect(value)}"

  defp format_error(other), do: "invalid tinfoil config: #{inspect(other)}"
end
