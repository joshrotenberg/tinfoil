defmodule Mix.Tasks.Tinfoil.Build do
  @shortdoc "Build one target and package it into a release archive"

  @moduledoc """
  Build a single tinfoil target end-to-end.

  Runs `mix release` with the appropriate `BURRITO_TARGET` for the
  requested target, then tars and checksums the output. Designed to
  be called once per CI matrix entry — the generated workflow invokes
  it that way.

  ## Examples

      mix tinfoil.build --target darwin_arm64
      MIX_ENV=prod mix tinfoil.build --target linux_x86_64

  ## Flags

    * `--target`       — required, the tinfoil target atom to build
    * `--skip-release` — skip `mix release` and package an existing
                         `burrito_out/<app>_<burrito_name>` binary
    * `--output-dir`   — directory for the archive (default `_tinfoil`)
  """

  use Mix.Task

  alias Tinfoil.{Build, Config, Target}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [target: :string, skip_release: :boolean, output_dir: :string]
      )

    target = parse_target(opts[:target])

    config =
      case Config.load(Mix.Project.config()) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("tinfoil config error: #{inspect(reason)}")
      end

    if target not in config.targets do
      Mix.raise("target #{inspect(target)} not in :tinfoil :targets (#{inspect(config.targets)})")
    end

    warn_if_not_prod()

    result =
      Build.run(config,
        target: target,
        skip_release: Keyword.get(opts, :skip_release, false),
        output_dir: Keyword.get(opts, :output_dir, "_tinfoil")
      )

    report(result)
  end

  defp parse_target(nil),
    do: Mix.raise("--target is required (e.g. --target darwin_arm64)")

  defp parse_target(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      Mix.raise("unknown --target #{inspect(string)}. Valid: #{inspect(Target.all())}")
  end

  defp warn_if_not_prod do
    if Mix.env() != :prod do
      Mix.shell().info([
        :yellow,
        "warning: building without MIX_ENV=prod is unusual for a release " <>
          "artifact. Use `MIX_ENV=prod mix tinfoil.build ...` in CI.\n",
        :reset
      ])
    end
  end

  defp report(result) do
    Mix.shell().info([
      :green,
      "* built ",
      :reset,
      result.archive,
      "\n",
      :green,
      "* sha256 ",
      :reset,
      result.sha256
    ])
  end
end
