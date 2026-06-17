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

      {:ok, %{skipped: :prerelease}} ->
        Mix.shell().info("skipping Scoop manifest update for prerelease tag #{tag(opts)}")

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
        Mix.raise("scoop publish failed: #{format_error(reason)}")
    end
  end

  defp tag(opts), do: Keyword.get(opts, :tag) || System.get_env("GITHUB_REF_NAME") || "(unknown)"

  defp format_error(:missing_tag),
    do: "no tag given (--tag) and GITHUB_REF_NAME is not set"

  defp format_error(:missing_scoop_bucket_token),
    do: "scoop.auth is :token but SCOOP_BUCKET_TOKEN is not set"

  defp format_error(:missing_windows_target),
    do: "scoop requires :windows_x86_64 in :targets, but it is not configured"

  defp format_error({:missing_sha_sidecar, target, path}),
    do: "missing #{target} checksum sidecar: #{path} (was the build artifact uploaded?)"

  defp format_error(:malformed_sha_sidecar),
    do: "a .sha256 sidecar did not contain a 64-character hex digest"

  defp format_error({:git_failed, args, status, output}),
    do: "git #{Enum.join(args, " ")} exited #{status}: #{String.trim(output)}"

  defp format_error(other), do: inspect(other)

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
