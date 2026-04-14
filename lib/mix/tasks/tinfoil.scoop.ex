defmodule Mix.Tasks.Tinfoil.Scoop do
  @shortdoc "Render and push the Scoop manifest to the configured bucket"

  @moduledoc """
  Render the Scoop manifest from release artifacts and push it to the
  configured bucket repo. The Windows counterpart to
  `mix tinfoil.homebrew`.

  Runs on a separate CI job after `mix tinfoil.publish` has created
  the GitHub Release. The heavy lifting lives in `Tinfoil.Scoop`.

  ## Required environment

    * `GITHUB_REF_NAME`         — release tag (`v1.2.3`)
    * `SCOOP_BUCKET_TOKEN`      — only when `scoop.auth` is `:token`

  When `scoop.auth` is `:deploy_key`, set up an `ssh-agent` with the
  bucket repo's deploy key before invoking the task (the generated
  workflow does this via `webfactory/ssh-agent`).

  ## Flags

    * `--input-dir DIR` — directory containing release archives and
      `.sha256` sidecars (default `"artifacts"`)
    * `--tag VALUE`     — override `GITHUB_REF_NAME`
    * `--dry-run`       — render the manifest and print what would be
      pushed (bucket, clone URL with tokens redacted, commit message,
      full manifest JSON) without touching the bucket repo
  """

  use Mix.Task

  alias Tinfoil.{Config, Scoop}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [input_dir: :string, tag: :string, dry_run: :boolean],
        aliases: [i: :input_dir]
      )

    config =
      case Config.load(Mix.Project.config()) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("tinfoil config error: #{inspect(reason)}")
      end

    if not config.scoop.enabled do
      Mix.raise("tinfoil :scoop is not enabled; set :enabled and :bucket in mix.exs")
    end

    case Scoop.publish(config, Keyword.new(opts)) do
      {:ok, %{dry_run: true} = preview} ->
        report_preview(preview)

      {:ok, %{pushed: false}} ->
        Mix.shell().info("manifest unchanged; nothing to push")

      {:ok, %{pushed: true, commit_sha: sha}} ->
        Mix.shell().info([
          :green,
          "* pushed #{config.app} #{config.version} to #{config.scoop.bucket} (",
          String.slice(sha, 0, 7),
          ")",
          :reset
        ])

      {:error, reason} ->
        Mix.raise("scoop publish failed: #{inspect(reason)}")
    end
  end

  defp report_preview(preview) do
    Mix.shell().info([:cyan, "tinfoil scoop (dry-run)\n", :reset])
    Mix.shell().info("  bucket:         #{preview.bucket}")
    Mix.shell().info("  auth:           #{preview.auth}")
    Mix.shell().info("  clone url:      #{preview.clone_url}")
    Mix.shell().info("  manifest name:  #{preview.manifest_name}")
    Mix.shell().info("  commit message: #{preview.commit_message}")
    Mix.shell().info("\n  manifest:")
    preview.manifest |> String.split("\n") |> Enum.each(&Mix.shell().info("    " <> &1))
    Mix.shell().info("\n  no git clone, commit, or push performed")
  end
end
