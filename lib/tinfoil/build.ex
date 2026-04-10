defmodule Tinfoil.Build do
  @moduledoc """
  Orchestrate a single-target Burrito build, archive, and checksum.

  A single `run/2` call is what one CI matrix entry does: resolve the
  tinfoil target to the user's Burrito name, run `mix release` with
  `BURRITO_TARGET` set, then locate the binary, tar.gz it, and write
  a sha256 sidecar.

  This module is the heart of the v0.2 "tool-in-the-loop" story: the
  generated workflow calls `mix tinfoil.build --target <atom>` once
  per matrix entry instead of embedding the packaging logic in bash.
  """

  alias Tinfoil.{Archive, Config, Target}

  @type opts :: [
          target: Target.target(),
          skip_release: boolean(),
          output_dir: Path.t()
        ]

  @type result :: %{
          target: Target.target(),
          burrito_name: atom(),
          binary: Path.t(),
          archive: Path.t(),
          sha256: String.t(),
          sha256_sidecar: Path.t()
        }

  @default_output_dir "_tinfoil"

  @doc """
  Build a single target end-to-end.

  Steps:

    1. Look up the user's Burrito target name for the tinfoil target.
    2. Unless `:skip_release` is set, export `BURRITO_TARGET` and run
       `mix release` in the current project.
    3. Locate `burrito_out/<app>_<burrito_name>` and tar.gz it into
       the output directory with the configured archive basename.
    4. Write a `.sha256` sidecar next to the archive.

  Returns a map describing what was produced.
  """
  @spec run(Config.t(), opts()) :: result()
  def run(%Config{} = config, opts) do
    target = Keyword.fetch!(opts, :target)
    skip_release = Keyword.get(opts, :skip_release, false)
    output_dir = Keyword.get(opts, :output_dir, @default_output_dir)
    burrito_name = Map.fetch!(config.burrito_names, target)

    info(["* tinfoil building ", to_string(target), " (burrito: ", to_string(burrito_name), ")"])

    if not skip_release do
      info("* running mix release")
      run_release(burrito_name)
    end

    binary = Path.join("burrito_out", "#{config.app}_#{burrito_name}")

    if not File.exists?(binary) do
      raise "no Burrito output at #{binary}. " <>
              "Did `mix release` succeed for BURRITO_TARGET=#{burrito_name}?"
    end

    info(["* packaging ", binary])
    archive_basename = Config.archive_basename(config, target)
    archive = Archive.tar_gz(binary, config.app, archive_basename, output_dir)
    {sha, sidecar} = Archive.sha256(archive)

    %{
      target: target,
      burrito_name: burrito_name,
      binary: binary,
      archive: archive,
      sha256: sha,
      sha256_sidecar: sidecar
    }
  end

  ## ───────────────────── internals ─────────────────────

  defp run_release(burrito_name) do
    System.put_env("BURRITO_TARGET", to_string(burrito_name))
    # --overwrite keeps mix release from prompting when an existing
    # release directory is present. tinfoil is an automation tool —
    # a prompt hang would deadlock CI without any useful signal.
    Mix.Task.run("release", ["--overwrite"])
    Mix.Task.reenable("release")
  end

  defp info(message) do
    Mix.shell().info([:cyan, message, :reset])
  end
end
