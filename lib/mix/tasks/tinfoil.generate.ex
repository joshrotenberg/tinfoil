defmodule Mix.Tasks.Tinfoil.Generate do
  @shortdoc "Regenerate the tinfoil release workflow from mix.exs config"

  @moduledoc """
  Regenerate the tinfoil-managed files from the current `:tinfoil`
  config in `mix.exs`.

  Run this after changing your tinfoil config (adding targets,
  enabling Homebrew, bumping the tinfoil dependency, etc).

  ## Flags

    * `--force`    — overwrite existing files (default: true)
    * `--dry-run`  — print the list of files that would be written
                     without touching the filesystem
  """

  use Mix.Task

  alias Tinfoil.{Config, Generator}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [force: :boolean, dry_run: :boolean]
      )

    config =
      case Config.load(Mix.Project.config()) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("tinfoil config error: #{inspect(reason)}")
      end

    if opts[:dry_run] do
      dry_run(config)
    else
      result = Generator.write!(config, force: Keyword.get(opts, :force, true))
      report(result)
    end
  end

  defp dry_run(config) do
    Mix.shell().info([:cyan, "# tinfoil.generate --dry-run\n", :reset])

    Enum.each(Generator.render(config), fn file ->
      Mix.shell().info([
        :green,
        "would write ",
        :reset,
        file.path,
        " (",
        to_string(byte_size(file.contents)),
        " bytes)"
      ])
    end)
  end

  defp report(%{written: written, skipped: skipped}) do
    Enum.each(written, fn p ->
      Mix.shell().info([:green, "* wrote ", :reset, p])
    end)

    Enum.each(skipped, fn p ->
      Mix.shell().info([:yellow, "* skipped ", :reset, p])
    end)
  end
end
