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

  alias Tinfoil.Target

  @enforce_keys [:app, :version, :targets]
  defstruct [
    :app,
    :version,
    :description,
    :homepage_url,
    :license,
    :targets,
    archive_name: "{app}-{version}-{target}",
    archive_format: :tar_gz,
    github: %{repo: nil, draft: false},
    homebrew: %{enabled: false, tap: nil, formula_name: nil},
    installer: %{enabled: false, install_dir: "~/.local/bin"},
    checksums: :sha256,
    ci: %{
      provider: :github_actions,
      elixir_version: "1.18",
      otp_version: "28",
      zig_version: "0.13.0"
    }
  ]

  @type t :: %__MODULE__{
          app: atom(),
          version: String.t(),
          description: String.t() | nil,
          homepage_url: String.t() | nil,
          license: String.t() | nil,
          targets: [Target.target()],
          archive_name: String.t(),
          archive_format: :tar_gz | :zip,
          github: map(),
          homebrew: map(),
          installer: map(),
          checksums: :sha256,
          ci: map()
        }

  @doc """
  Load and resolve the config from a mix project keyword list.

  Accepts the return value of `Mix.Project.config/0` (or an equivalent
  keyword list in tests). Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(project) when is_list(project) do
    with {:ok, tinfoil} <- fetch_tinfoil(project),
         {:ok, targets} <- fetch_targets(tinfoil),
         :ok <- Target.validate(targets) do
      config = %__MODULE__{
        app: Keyword.fetch!(project, :app),
        version: Keyword.fetch!(project, :version),
        description: Keyword.get(project, :description),
        homepage_url: Keyword.get(project, :homepage_url),
        license: extract_license(project),
        targets: targets,
        archive_name: Keyword.get(tinfoil, :archive_name, "{app}-{version}-{target}"),
        archive_format: Keyword.get(tinfoil, :archive_format, :tar_gz),
        github: merge_github(Keyword.get(tinfoil, :github, [])),
        homebrew: merge_homebrew(Keyword.get(tinfoil, :homebrew, []), project),
        installer: merge_installer(Keyword.get(tinfoil, :installer, [])),
        checksums: Keyword.get(tinfoil, :checksums, :sha256),
        ci: merge_ci(Keyword.get(tinfoil, :ci, []))
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
    triple = Target.triple(target)

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

  defp merge_ci(user) do
    defaults = %{
      provider: :github_actions,
      elixir_version: "1.18",
      otp_version: "28",
      zig_version: "0.13.0"
    }

    Map.merge(defaults, Map.new(user))
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
      "Valid targets: #{inspect(Target.all())}"
  end

  defp format_error(other), do: "invalid tinfoil config: #{inspect(other)}"
end
