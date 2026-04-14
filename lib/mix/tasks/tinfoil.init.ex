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

  # Splice the tinfoil dep and :tinfoil config into mix.exs, then
  # re-fetch deps. The edits are atomic: if either splice can't find
  # its anchor, the file is left untouched and we fall back to the
  # manual snippet.
  defp install_into_mix_exs do
    path = "mix.exs"

    unless File.regular?(path) do
      Mix.raise("mix.exs not found in #{File.cwd!()}")
    end

    source = File.read!(path)

    with {:ok, with_dep, dep_status} <-
           ProjectEditor.insert_dep(source, tinfoil_version()),
         {:ok, with_config, config_status} <-
           ProjectEditor.insert_tinfoil_config(with_dep, default_targets()) do
      if source == with_config do
        Mix.shell().info("mix.exs already references tinfoil; nothing to do")
      else
        File.write!(path, with_config)
        report_install(dep_status, config_status)
        Mix.shell().info([:cyan, "* running mix deps.get", :reset])
        Mix.Task.run("deps.get")
        Mix.shell().info([:cyan, "\nNow re-run ", :reset, "mix tinfoil.init"])
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

  defp report_install(dep_status, config_status) do
    Mix.shell().info([
      :green,
      "* dep: ",
      :reset,
      to_string(dep_status),
      :green,
      "  * config: ",
      :reset,
      to_string(config_status)
    ])
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
