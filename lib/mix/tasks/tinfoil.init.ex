defmodule Mix.Tasks.Tinfoil.Init do
  @shortdoc "Scaffold tinfoil config and generate the release workflow"

  @moduledoc """
  Initialize tinfoil for the current mix project.

  This is the starting point. It will:

    1. Check whether the project already has a `:tinfoil` config in
       `mix.exs`; if not, print a config snippet to add.
    2. If a config is already present, generate the release pipeline
       files:

         * `.github/workflows/release.yml`
         * `scripts/install.sh`         (if `:installer` enabled)
         * `scripts/update-homebrew.sh` (if `:homebrew` enabled)
         * `.tinfoil/formula.rb.eex`    (if `:homebrew` enabled)

  ## Flags

    * `--force`  — overwrite existing generated files (default: true)
    * `--print`  — print the suggested config snippet and exit
  """

  use Mix.Task

  alias Tinfoil.{Config, Generator, Target}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, switches: [force: :boolean, print: :boolean])

    project = Mix.Project.config()

    cond do
      opts[:print] ->
        print_snippet(project)

      not has_tinfoil_config?(project) ->
        Mix.shell().info([
          :yellow,
          "no :tinfoil config found in mix.exs\n",
          :reset
        ])

        print_snippet(project)

        Mix.shell().info("""

        Add the snippet above to your `project/0` in mix.exs, then run:

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

  defp default_targets, do: Target.all()

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
