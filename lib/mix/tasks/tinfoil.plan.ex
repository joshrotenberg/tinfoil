defmodule Mix.Tasks.Tinfoil.Plan do
  @shortdoc "Show what tinfoil would build and release"

  @moduledoc """
  Print a plan of what tinfoil would build and release from the
  current `:tinfoil` config in `mix.exs`.

  This is a read-only task: it touches no files, makes no network
  calls, and does not run a build. It is safe to run anywhere.

  ## Formats

    * `--format human`  — readable table (default)
    * `--format json`   — full plan as pretty-printed JSON
    * `--format matrix` — GitHub Actions matrix fragment (compact JSON)

  The matrix format is the shape GitHub Actions expects for
  `strategy.matrix` via `fromJson()`:

      - id: plan
        run: echo "matrix=$(mix tinfoil.plan --format matrix)" >> "$GITHUB_OUTPUT"

      build:
        needs: plan
        strategy:
          matrix: ${{ fromJson(needs.plan.outputs.matrix) }}

  ## Examples

      mix tinfoil.plan
      mix tinfoil.plan --format json
      mix tinfoil.plan --format matrix
  """

  use Mix.Task

  alias Tinfoil.{Config, NifCheck, Plan}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [format: :string],
        aliases: [f: :format]
      )

    config =
      case Config.load(Mix.Project.config()) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("tinfoil config error: #{inspect(reason)}")
      end

    plan = Plan.build(config)

    case Keyword.get(opts, :format, "human") do
      "human" ->
        Mix.shell().info(render_human(plan))
        warn_nifs()

      "json" ->
        Mix.shell().info(Jason.encode!(plan, pretty: true))

      "matrix" ->
        Mix.shell().info(Jason.encode!(Plan.matrix(plan)))

      other ->
        Mix.raise("unknown --format: #{inspect(other)} (expected human, json, or matrix)")
    end
  end

  defp warn_nifs do
    # Scan the deps the release will actually contain, not the ones this
    # task happens to see. `plan` runs in dev; the build runs in prod, so
    # dev/test-only deps here would be false positives.
    case NifCheck.check(NifCheck.release_deps(:prod)) do
      [] ->
        :ok

      warnings ->
        Mix.shell().info("")
        Mix.shell().info("  NIF warnings (may not cross-compile cleanly):")

        Enum.each(warnings, &print_warning/1)
    end
  end

  defp print_warning(%{name: name, reasons: reasons}) do
    Enum.each(reasons, fn reason ->
      Mix.shell().info("    #{name}: #{NifCheck.describe(reason)}")
    end)
  end

  @doc false
  def render_human(plan) do
    [
      header(plan),
      "",
      target_table(plan.targets),
      "",
      extras(plan)
    ]
    |> Enum.join("\n")
  end

  defp header(plan) do
    "tinfoil plan for #{plan.app} #{plan.version}"
  end

  defp target_table(targets) do
    rows =
      Enum.map(targets, fn t ->
        [to_string(t.target), to_string(t.burrito_name), t.runner, t.archive]
      end)

    headers = ["target", "burrito", "runner", "archive"]
    widths = column_widths([headers | rows])
    separator = "  " <> Enum.map_join(widths, "  ", &String.duplicate("─", &1))

    header_lines = [format_row(headers, widths), separator]
    data_lines = Enum.map(rows, &format_row(&1, widths))

    Enum.join(header_lines ++ data_lines, "\n")
  end

  defp column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn col ->
      col |> Tuple.to_list() |> Enum.map(&String.length/1) |> Enum.max()
    end)
  end

  defp format_row(cells, widths) do
    padded =
      cells
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)

    "  " <> padded
  end

  defp extras(plan) do
    [
      "format:    #{plan.archive_format} (#{plan.checksums})",
      "trigger:   #{trigger_line(plan.trigger)}",
      "github:    #{github_line(plan.github)}",
      "homebrew:  #{homebrew_line(plan.homebrew)}",
      "scoop:     #{scoop_line(plan.scoop)}",
      "installer: #{installer_line(plan.installer)}"
    ]
    |> Enum.map_join("\n", &("  " <> &1))
  end

  defp trigger_line(:tag_push), do: "tag push v* (tinfoil creates the release)"
  defp trigger_line(:release_published), do: "release published (tinfoil attaches assets)"

  defp github_line(%{repo: nil}), do: "(unresolved — set :github, :repo in mix.exs)"
  defp github_line(%{repo: repo, draft: draft}), do: "#{repo} (draft: #{draft})"

  defp homebrew_line(%{enabled: false}), do: "disabled"

  defp homebrew_line(%{enabled: true, tap: tap, formula_name: name}) do
    "tap #{tap || "(unset)"} (formula: #{name})"
  end

  defp scoop_line(%{enabled: false}), do: "disabled"

  defp scoop_line(%{enabled: true, bucket: bucket, manifest_name: name}) do
    "bucket #{bucket || "(unset)"} (manifest: #{name})"
  end

  defp installer_line(%{enabled: false}), do: "disabled"
  defp installer_line(%{enabled: true, install_dir: dir}), do: dir
end
