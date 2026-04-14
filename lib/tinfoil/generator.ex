defmodule Tinfoil.Generator do
  @moduledoc """
  Renders tinfoil's EEx templates into the target project.

  The generator is the mechanical half of `mix tinfoil.init` and
  `mix tinfoil.generate`: it takes a `%Tinfoil.Config{}` and writes
  (or returns) the files that make up the generated release pipeline:

    * `.github/workflows/release.yml`
    * `scripts/install.sh`            (if installer enabled)
    * `.tinfoil/formula.rb.eex`       (if homebrew enabled)
  """

  alias Tinfoil.Config

  # Templates are compiled into this module at build time via
  # `EEx.function_from_file/5` — that's the only distribution shape
  # that's bulletproof across hex deps, path deps, Burrito wraps, AND
  # local mix archives (archives only bundle ebin/, so neither a
  # source `lib/` path nor `priv/` would be available at runtime).
  #
  # We recompile this module when any template changes so edits during
  # development don't require a manual `touch`.
  @templates_dir Path.expand("../../priv/templates", __DIR__)
  @external_resource Path.join(@templates_dir, "release.yml.eex")
  @external_resource Path.join(@templates_dir, "formula.rb.eex")
  @external_resource Path.join(@templates_dir, "install.sh.eex")
  @external_resource Path.join(@templates_dir, "install.ps1.eex")
  @external_resource Path.join(@templates_dir, "scoop.json.eex")
  @external_resource Path.join(@templates_dir, "application.ex.eex")
  @external_resource Path.join(@templates_dir, "cli.ex.eex")

  require EEx

  EEx.function_from_file(
    :defp,
    :render_release_yml,
    Path.join(@templates_dir, "release.yml.eex"),
    [
      :assigns
    ]
  )

  EEx.function_from_file(:defp, :render_formula_rb, Path.join(@templates_dir, "formula.rb.eex"), [
    :assigns
  ])

  EEx.function_from_file(:defp, :render_install_sh, Path.join(@templates_dir, "install.sh.eex"), [
    :assigns
  ])

  EEx.function_from_file(
    :defp,
    :render_install_ps1,
    Path.join(@templates_dir, "install.ps1.eex"),
    [
      :assigns
    ]
  )

  EEx.function_from_file(:defp, :render_scoop_json, Path.join(@templates_dir, "scoop.json.eex"), [
    :assigns
  ])

  EEx.function_from_file(
    :defp,
    :render_application_ex,
    Path.join(@templates_dir, "application.ex.eex"),
    [:assigns]
  )

  EEx.function_from_file(:defp, :render_cli_ex, Path.join(@templates_dir, "cli.ex.eex"), [
    :assigns
  ])

  @type generated :: %{path: Path.t(), contents: String.t(), executable: boolean()}

  @doc """
  Return the list of generated files as `{path, contents, executable?}`
  tuples relative to the project root, without touching the filesystem.
  """
  @spec render(Config.t()) :: [generated()]
  def render(%Config{} = config) do
    files = [
      %{
        path: ".github/workflows/release.yml",
        contents: render_workflow(config),
        executable: false
      }
    ]

    files =
      if config.homebrew.enabled do
        files ++
          [
            %{
              path: ".tinfoil/formula.rb.eex",
              contents: render_formula(config),
              executable: false
            }
          ]
      else
        files
      end

    files =
      if config.installer.enabled do
        files ++
          [
            %{
              path: "scripts/install.sh",
              contents: render_installer(config),
              executable: true
            },
            %{
              path: "scripts/install.ps1",
              contents: render_installer_powershell(config),
              # .ps1 doesn't need a Unix executable bit; PowerShell's
              # own execution policy gates whether it runs.
              executable: false
            }
          ]
      else
        files
      end

    files
  end

  @doc """
  Write all generated files into `root` (defaults to the current
  working directory). Returns `{written, skipped}` where each is a
  list of relative paths.

  Existing files are overwritten unless `force: false` is passed and
  the existing file differs from the generated contents (in which
  case it is skipped and reported).
  """
  @spec write!(Config.t(), keyword()) :: %{written: [Path.t()], skipped: [Path.t()]}
  def write!(%Config{} = config, opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    force = Keyword.get(opts, :force, true)

    config
    |> render()
    |> Enum.reduce(%{written: [], skipped: []}, &write_one(&1, root, force, &2))
    |> Map.update!(:written, &Enum.reverse/1)
    |> Map.update!(:skipped, &Enum.reverse/1)
  end

  defp write_one(file, root, force, acc) do
    target = Path.join(root, file.path)
    File.mkdir_p!(Path.dirname(target))

    if skip?(target, force, file.contents) do
      %{acc | skipped: [file.path | acc.skipped]}
    else
      File.write!(target, file.contents)
      if file.executable, do: File.chmod!(target, 0o755)
      %{acc | written: [file.path | acc.written]}
    end
  end

  defp skip?(target, force, contents) do
    File.exists?(target) and not force and File.read!(target) != contents
  end

  ## ───────────── individual template renderers ─────────────

  @doc false
  @spec render_workflow(Config.t()) :: String.t()
  def render_workflow(%Config{} = config) do
    plan = Tinfoil.Plan.build(config)

    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      build_entries: Tinfoil.Plan.build_entries(plan),
      ci: config.ci,
      github: config.github,
      homebrew: config.homebrew,
      scoop: config.scoop,
      attestations: config.attestations
    ]

    render_release_yml(assigns)
  end

  @doc false
  @spec render_formula(Config.t()) :: String.t()
  def render_formula(%Config{} = config) do
    repo = config.github.repo || "OWNER/REPO"

    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      formula_name: config.homebrew.formula_name,
      formula_class: formula_class(config.homebrew.formula_name),
      description: config.description || "#{config.app} CLI",
      homepage: config.homepage_url || "https://github.com/#{repo}",
      license: config.license || "MIT",
      base_url: "https://github.com/#{repo}/releases",
      targets: config.targets
    ]

    render_formula_rb(assigns)
  end

  @doc false
  @spec render_installer(Config.t()) :: String.t()
  def render_installer(%Config{} = config) do
    repo = config.github.repo || "OWNER/REPO"

    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      repo: repo,
      install_dir: config.installer.install_dir,
      raw_url: "https://raw.githubusercontent.com/#{repo}/main/scripts/install.sh"
    ]

    render_install_sh(assigns)
  end

  @doc false
  @spec render_installer_powershell(Config.t()) :: String.t()
  def render_installer_powershell(%Config{} = config) do
    repo = config.github.repo || "OWNER/REPO"

    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      repo: repo,
      install_dir: config.installer.install_dir,
      raw_ps_url: "https://raw.githubusercontent.com/#{repo}/main/scripts/install.ps1"
    ]

    render_install_ps1(assigns)
  end

  @doc false
  @spec render_scoop(keyword()) :: String.t()
  def render_scoop(assigns), do: render_scoop_json(assigns)

  @doc """
  Render the `lib/<app>/application.ex` boilerplate used by
  `mix tinfoil.init --install`. Not part of `render/1` because this
  is a one-time scaffolding artifact, not something to regenerate on
  every `mix tinfoil.generate`.
  """
  @spec render_application(atom()) :: String.t()
  def render_application(app) when is_atom(app) do
    assigns = [
      app: app,
      app_module: app_module(app)
    ]

    render_application_ex(assigns)
  end

  @doc """
  Render a stub `lib/<app>/cli.ex` that `<App>.Application.start/2`
  calls. Gives a fresh project something runnable before the user
  writes their real command tree.
  """
  @spec render_cli(atom()) :: String.t()
  def render_cli(app) when is_atom(app) do
    assigns = [
      app: app,
      app_module: app_module(app)
    ]

    render_cli_ex(assigns)
  end

  @doc """
  Return the CamelCase module name for an app atom (`:my_cli` -> `"MyCli"`).
  """
  @spec app_module(atom()) :: String.t()
  def app_module(app) when is_atom(app) do
    app
    |> Atom.to_string()
    |> Macro.camelize()
  end

  ## ───────────── internals ─────────────

  defp tinfoil_version do
    case Application.spec(:tinfoil, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  # Turn "my_cli" / "my-cli" into "MyCli" for the formula class name.
  defp formula_class(name) do
    name
    |> to_string()
    |> String.split(~r/[-_]/)
    |> Enum.map_join("", &String.capitalize/1)
  end
end
