defmodule Tinfoil.Generator do
  @moduledoc """
  Renders tinfoil's EEx templates into the target project.

  The generator is the mechanical half of `mix tinfoil.init` and
  `mix tinfoil.generate`: it takes a `%Tinfoil.Config{}` and writes
  (or returns) the files that make up the generated release pipeline:

    * `.github/workflows/release.yml`
    * `scripts/install.sh`            (if installer enabled)
    * `scripts/update-homebrew.sh`    (if homebrew enabled)
    * `.tinfoil/formula.rb.eex`       (if homebrew enabled)
  """

  alias Tinfoil.Config

  @templates_dir Path.join([__DIR__, "templates"])

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
            },
            %{
              path: "scripts/update-homebrew.sh",
              contents: render_update_homebrew(config),
              executable: true
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
  def render_workflow(%Config{} = config) do
    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      targets: config.targets,
      burrito_names: config.burrito_names,
      ci: config.ci,
      github: config.github,
      homebrew: config.homebrew,
      archive_basename_template: config.archive_name,
      archive_ext: Config.archive_extension(config)
    ]

    eval("release.yml.eex", assigns)
  end

  @doc false
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

    eval("formula.rb.eex", assigns)
  end

  @doc false
  def render_installer(%Config{} = config) do
    repo = config.github.repo || "OWNER/REPO"

    assigns = [
      tinfoil_version: tinfoil_version(),
      app: config.app,
      repo: repo,
      install_dir: config.installer.install_dir,
      raw_url: "https://raw.githubusercontent.com/#{repo}/main/scripts/install.sh"
    ]

    eval("install.sh.eex", assigns)
  end

  @doc false
  def render_update_homebrew(%Config{} = config) do
    assigns = [
      tinfoil_version: tinfoil_version(),
      formula_name: config.homebrew.formula_name
    ]

    eval("update_homebrew.sh.eex", assigns)
  end

  ## ───────────── internals ─────────────

  defp eval(name, assigns) do
    path = Path.join(@templates_dir, name)
    EEx.eval_file(path, assigns: assigns)
  end

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
