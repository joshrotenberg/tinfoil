defmodule Mix.Tasks.Tinfoil.Init do
  @shortdoc "Scaffold tinfoil config and generate the release workflow"

  @moduledoc """
  Initialize tinfoil for the current mix project.

  By default, if no `:tinfoil` config is found in `mix.exs`, this
  task prints a snippet to paste and exits. If a config is already
  present, it generates the release pipeline files:

    * `.github/workflows/release.yml`
    * `.tinfoil/formula.rb.eex`    (if `:homebrew` enabled)
    * `scripts/install.sh`         (if `:installer` enabled)

  ## Flags

    * `--install` — splice `{:tinfoil, ...}` into `deps/0` and a
      minimal `:tinfoil` config into `project/0`, then run
      `mix deps.get`. Only touches `mix.exs` files that still match
      the `mix new` layout; on anything more customized it falls
      back to printing the snippet.
    * `--force`   — overwrite existing generated files (default: true)
    * `--print`   — print the suggested config snippet and exit
  """

  use Mix.Task

  alias Tinfoil.{Config, Generator, ProjectEditor, Target}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [force: :boolean, print: :boolean, install: :boolean]
      )

    project = Mix.Project.config()

    cond do
      opts[:print] ->
        print_snippet(project)

      Keyword.get(opts, :install, false) and not has_tinfoil_config?(project) ->
        install_into_mix_exs()

      not has_tinfoil_config?(project) ->
        Mix.shell().info([
          :yellow,
          "no :tinfoil config found in mix.exs\n",
          :reset
        ])

        print_snippet(project)

        Mix.shell().info("""

        Add the snippet above to your `project/0` in mix.exs (or run
        `mix tinfoil.init --install` to do it automatically), then:

            mix tinfoil.init
        """)

      true ->
        case Config.load(project) do
          {:ok, config} ->
            result = Generator.write!(config, force: Keyword.get(opts, :force, true))
            report(result)
            next_steps(config)

          {:error, reason} ->
            Mix.raise("tinfoil config error: #{inspect(reason)}")
        end
    end
  end

  # Splice the tinfoil dep, Burrito dep + releases block, :tinfoil
  # config, and Application callback module into mix.exs (and the
  # filesystem), then re-fetch deps. Each splice is idempotent, so
  # re-running `--install` only fills in what's missing.
  defp install_into_mix_exs do
    path = "mix.exs"

    unless File.regular?(path) do
      Mix.raise("mix.exs not found in #{File.cwd!()}")
    end

    project = Mix.Project.config()
    app = Keyword.fetch!(project, :app)
    app_module = Generator.app_module(app)
    targets = default_targets()

    source = File.read!(path)

    with {:ok, s1, s_tinfoil} <- ProjectEditor.insert_tinfoil_dep(source, tinfoil_version()),
         {:ok, s2, s_burrito} <- ProjectEditor.insert_burrito_dep(s1),
         {:ok, s3, s_config} <- ProjectEditor.insert_tinfoil_config(s2, targets),
         {:ok, s4, s_rel_entry} <- ProjectEditor.insert_releases_entry(s3),
         {:ok, s5, s_rel_block} <- ProjectEditor.insert_releases_block(s4, app, targets),
         {:ok, new_source, s_app_mod} <-
           ProjectEditor.insert_application_mod(s5, app_module) do
      changed = new_source != source

      if changed do
        File.write!(path, new_source)
      end

      application_status =
        write_scaffold_file(app, "application.ex", &Generator.render_application/1)

      cli_status = write_scaffold_file(app, "cli.ex", &Generator.render_cli/1)

      statuses = [
        {"tinfoil dep", s_tinfoil},
        {"burrito dep", s_burrito},
        {"tinfoil config", s_config},
        {"releases entry", s_rel_entry},
        {"releases block", s_rel_block},
        {"application mod", s_app_mod},
        {"application.ex", application_status},
        {"cli.ex", cli_status}
      ]

      report_install(statuses)

      if changed or application_status == :inserted or cli_status == :inserted do
        Mix.shell().info([:cyan, "\n* running mix deps.get", :reset])
        Mix.Task.run("deps.get")
        Mix.shell().info([:cyan, "\nNow re-run ", :reset, "mix tinfoil.init"])
      else
        Mix.shell().info("mix.exs already fully scaffolded; nothing to do")
      end
    else
      {:error, reason} ->
        Mix.shell().info([
          :yellow,
          "could not auto-edit mix.exs (#{inspect(reason)}); paste manually:\n",
          :reset
        ])

        print_snippet(Mix.Project.config())
    end
  end

  # Write a scaffolding file under lib/<app>/ if it doesn't already
  # exist. Never overwrites — a user who's customized the file should
  # keep their version, and re-running `--install` shouldn't clobber
  # hand edits.
  defp write_scaffold_file(app, filename, renderer) do
    relative = Path.join(["lib", to_string(app), filename])

    if File.exists?(relative) do
      :already_present
    else
      File.mkdir_p!(Path.dirname(relative))
      File.write!(relative, renderer.(app))
      :inserted
    end
  end

  defp report_install(statuses) do
    Enum.each(statuses, fn {label, status} ->
      color = if status == :inserted, do: :green, else: :yellow
      Mix.shell().info([color, "* #{label}: ", :reset, to_string(status)])
    end)
  end

  defp tinfoil_version do
    case Application.spec(:tinfoil, :vsn) do
      nil -> "0.2"
      vsn -> vsn |> to_string() |> String.split(".") |> Enum.take(2) |> Enum.join(".")
    end
  end

  defp has_tinfoil_config?(project), do: Keyword.has_key?(project, :tinfoil)

  defp print_snippet(project) do
    app = Keyword.get(project, :app, :my_cli)

    snippet = """
        tinfoil: [
          targets: #{inspect(default_targets(), limit: :infinity)},
          homebrew: [
            enabled: false,
            tap: "#{owner_from_remote() || "OWNER"}/homebrew-tap"
          ],
          installer: [
            enabled: true
          ]
        ]
    """

    Mix.shell().info([
      :cyan,
      "\n# Suggested :tinfoil config for #{inspect(app)}:\n",
      :reset,
      snippet
    ])
  end

  defp default_targets, do: Target.builtin()

  defp owner_from_remote do
    case Config.infer_github_repo() do
      nil -> nil
      repo -> repo |> String.split("/") |> List.first()
    end
  end

  defp report(%{written: written, skipped: skipped}) do
    Enum.each(written, fn p ->
      Mix.shell().info([:green, "* created ", :reset, p])
    end)

    Enum.each(skipped, fn p ->
      Mix.shell().info([:yellow, "* skipped ", :reset, p, " (already exists)"])
    end)
  end

  defp next_steps(config) do
    steps =
      [
        "Review .github/workflows/release.yml",
        config.homebrew.enabled &&
          "Add HOMEBREW_TAP_TOKEN secret to your GitHub repo " <>
            "(PAT with repo access to #{config.homebrew.tap})",
        "Commit the generated files",
        "Tag a release: git tag v#{config.version} && git push --tags"
      ]
      |> Enum.reject(&(&1 == false or is_nil(&1)))
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, i} -> "  #{i}. #{step}" end)

    Mix.shell().info([:cyan, "\nNext steps:\n", :reset, steps, "\n"])
  end
end
