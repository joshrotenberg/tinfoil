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
      raise missing_binary_message(binary, config.app, burrito_name)
    end

    info(["* packaging ", binary])
    archive_basename = Config.archive_basename(config, target)
    archive_ext = Config.archive_extension(config, target)

    archive =
      package(
        archive_ext,
        binary,
        config.app,
        binary_ext,
        archive_basename,
        output_dir,
        config.extra_artifacts
      )

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
  Check that the release tag matches the given version.

  The tag comes from `opts[:tag]` if given, otherwise from the
  `GITHUB_REF_NAME` environment variable. Explicit beats env, matching
  how `Tinfoil.Publish`, `Tinfoil.Homebrew`, and `Tinfoil.Scoop` resolve
  the tag.

  Returns:

    * `:ok` — no tag available, or the tag matches
    * `{:skip, message}` — the tag is not version-shaped, so there is
      nothing meaningful to compare. Callers should warn and continue.
    * `{:error, message}` — a real mismatch
  """
  @spec validate_tag_version(String.t(), keyword()) ::
          :ok | {:skip, String.t()} | {:error, String.t()}
  def validate_tag_version(mix_version, opts \\ []) do
    case resolve_tag(opts) do
      :none -> :ok
      {:ok, source, tag} -> compare_tag(source, tag, mix_version)
    end
  end

  # Blank is treated as absent so a workflow that interpolates an unset
  # GitHub expression into `--tag ""` degrades to the env var rather than
  # comparing against nothing.
  defp resolve_tag(opts) do
    explicit = blank_to_nil(Keyword.get(opts, :tag))
    env = blank_to_nil(System.get_env("GITHUB_REF_NAME"))

    cond do
      explicit -> {:ok, :flag, explicit}
      env -> {:ok, :env, env}
      true -> :none
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp compare_tag(source, tag, mix_version) do
    tag_version = String.trim_leading(tag, "v")

    cond do
      tag_version == mix_version -> :ok
      not version_shaped?(tag_version) -> {:skip, not_a_tag_message(source, tag)}
      true -> {:error, mismatch_message(tag, mix_version)}
    end
  end

  # A ref that does not even start with digits is a branch name, not a
  # botched tag. Reporting it as a version skew sends people to bump
  # mix.exs or re-tag, and neither is the problem.
  defp version_shaped?(candidate), do: Regex.match?(~r/^\d+\./, candidate)

  defp mismatch_message(tag, mix_version) do
    "tag #{tag} does not match mix.exs version #{mix_version}. " <>
      "Bump the version in mix.exs or re-tag."
  end

  defp not_a_tag_message(:flag, tag) do
    "--tag #{inspect(tag)} is not a version tag, so the mix.exs version " <>
      "check was skipped."
  end

  defp not_a_tag_message(:env, ref) do
    """
    GITHUB_REF_NAME is #{inspect(ref)}, which is not a version tag, so the
    mix.exs version check was skipped.

    A `workflow_call` run inherits the calling workflow's ref, so this is
    the caller's branch rather than the tag. The generated workflow passes
    `--tag` for that trigger; if yours does not, regenerate it with
    `mix tinfoil.generate`.
    """
  end

  ## ───────────────────── internals ─────────────────────

  # Burrito appends .exe to the wrapped binary on Windows targets; other
  # targets have no extension on the output name.
  defp binary_extension(%{os_family: :windows}), do: ".exe"
  defp binary_extension(_), do: ""

  # Pick the packer based on the archive extension resolved for this target.
  # The binary's own extension (.exe on Windows) is preserved inside the
  # archive so `unzip` produces a runnable file. Extra files configured
  # via :extra_artifacts are bundled alongside the main binary.
  defp package(".zip", binary, app, binary_ext, basename, output_dir, extras) do
    Archive.zip(binary, "#{app}#{binary_ext}", basename, output_dir, extras)
  end

  defp package(".tar.gz", binary, app, _binary_ext, basename, output_dir, extras) do
    Archive.tar_gz(binary, app, basename, output_dir, extras)
  end

  # Two very different failures land here. Either `mix release` genuinely
  # failed, or it succeeded and produced a plain OTP release because
  # Burrito's wrap step never ran. The second case used to report the
  # first, which sends people to look at a release that worked fine.
  #
  # An assembled release directory alongside a missing burrito_out binary
  # is a reliable signal for the second case, and it is cheap to check.
  @doc false
  @spec missing_binary_message(Path.t(), atom(), atom()) :: String.t()
  def missing_binary_message(binary, app, burrito_name) do
    rel = Path.join([Mix.Project.build_path(), "rel", to_string(app)])

    if File.dir?(rel) do
      assembled_without_wrap_message(binary, rel)
    else
      "no Burrito output at #{binary}. " <>
        "Did `mix release` succeed for BURRITO_TARGET=#{burrito_name}?"
    end
  end

  defp assembled_without_wrap_message(binary, rel) do
    """
    no Burrito output at #{binary}, but an assembled release exists at #{rel}.

    `mix release` succeeded and produced a plain OTP release, so Burrito's
    wrap step did not run for this target.

    The usual cause is a `steps:` gate on BURRITO_TARGET in mix.exs:

        steps: if(System.get_env("BURRITO_TARGET"),
                 do: [:assemble, &Burrito.wrap/1],
                 else: [:assemble])

    mix.exs is evaluated at Mix startup, before any task runs, so
    BURRITO_TARGET is always nil while releases/0 is being built --
    tinfoil sets it inside the task, which is already too late. The gate
    silently takes the else branch.

    Gate on the invoked task instead, since argv IS populated by then:

        defp burrito_build? do
          System.get_env("BURRITO_TARGET") != nil or
            match?(["tinfoil.build" | _], System.argv())
        end

    If your release is unconditional, check that `&Burrito.wrap/1` is in
    its `steps:` and that the release name matches the app name.
    """
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
