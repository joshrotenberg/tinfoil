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

  alias Tinfoil.{Config, Plan}

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

      "json" ->
        Mix.shell().info(Jason.encode!(plan, pretty: true))

      "matrix" ->
        Mix.shell().info(Jason.encode!(Plan.matrix(plan)))

      other ->
        Mix.raise("unknown --format: #{inspect(other)} (expected human, json, or matrix)")
    end
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
      "github:    #{github_line(plan.github)}",
      "homebrew:  #{homebrew_line(plan.homebrew)}",
      "installer: #{installer_line(plan.installer)}"
    ]
    |> Enum.map_join("\n", &("  " <> &1))
  end

  defp github_line(%{repo: nil}), do: "(unresolved — set :github, :repo in mix.exs)"
  defp github_line(%{repo: repo, draft: draft}), do: "#{repo} (draft: #{draft})"

  defp homebrew_line(%{enabled: false}), do: "disabled"

  defp homebrew_line(%{enabled: true, tap: tap, formula_name: name}) do
    "tap #{tap || "(unset)"} (formula: #{name})"
  end

  defp installer_line(%{enabled: false}), do: "disabled"
  defp installer_line(%{enabled: true, install_dir: dir}), do: dir
end
