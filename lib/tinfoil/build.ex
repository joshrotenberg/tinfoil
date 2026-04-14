defmodule Tinfoil.Build do
  @moduledoc """
  Orchestrate a single-target Burrito build, archive, and checksum.

  A single `run/2` call is what one CI matrix entry does: resolve the
  tinfoil target to the user's Burrito name, run `mix release` with
  `BURRITO_TARGET` set, then locate the binary, tar.gz it, and write
  a sha256 sidecar.

  This module is the heart of tinfoil's tool-in-the-loop story: the
  generated workflow calls `mix tinfoil.build --target <atom>` once
  per matrix entry instead of embedding the packaging logic in bash,
  so upgrading tinfoil upgrades the pipeline.
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

    spec = Target.spec!(target, config.extra_targets)
    binary_ext = binary_extension(spec)
    binary = Path.join("burrito_out", "#{config.app}_#{burrito_name}#{binary_ext}")

    if not File.exists?(binary) do
      raise "no Burrito output at #{binary}. " <>
              "Did `mix release` succeed for BURRITO_TARGET=#{burrito_name}?"
    end

    info(["* packaging ", binary])
    archive_basename = Config.archive_basename(config, target)
    archive = package(spec, binary, config.app, archive_basename, output_dir)
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

  @doc """
  Check that the `GITHUB_REF_NAME` tag (if set) matches the given version.

  Returns `:ok` when the env var is unset or the versions match.
  Returns `{:error, message}` on mismatch.
  """
  @spec validate_tag_version(String.t()) :: :ok | {:error, String.t()}
  def validate_tag_version(mix_version) do
    case System.get_env("GITHUB_REF_NAME") do
      nil ->
        :ok

      tag ->
        tag_version = String.trim_leading(tag, "v")

        if tag_version == mix_version do
          :ok
        else
          {:error,
           "tag #{tag} does not match mix.exs version #{mix_version}. " <>
             "Bump the version in mix.exs or re-tag."}
        end
    end
  end

  ## ───────────────────── internals ─────────────────────

  # Burrito appends .exe to the wrapped binary on Windows targets; other
  # targets have no extension on the output name.
  defp binary_extension(%{os_family: :windows}), do: ".exe"
  defp binary_extension(_), do: ""

  # Pick the archive format from the target spec. Windows uses zip; every
  # other target produces tar.gz.
  defp package(%{archive_ext: ".zip"}, binary, app, basename, output_dir) do
    # Windows binaries carry the .exe suffix inside the archive too.
    name_in_archive = "#{app}.exe"
    Archive.zip(binary, name_in_archive, basename, output_dir)
  end

  defp package(_spec, binary, app, basename, output_dir) do
    Archive.tar_gz(binary, app, basename, output_dir)
  end

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
