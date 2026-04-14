defmodule Mix.Tasks.Tinfoil.Homebrew do
  @shortdoc "Render and push the Homebrew formula to the configured tap"

  @moduledoc """
  Render the Homebrew formula from the release artifacts in the input
  directory and push the result to the configured tap repo.

  Runs on a separate CI job after `mix tinfoil.publish` has created
  the GitHub Release. The heavy lifting lives in `Tinfoil.Homebrew`;
  this task is just a thin Mix wrapper.

  ## Required environment

    * `GITHUB_REF_NAME`     — release tag (`v1.2.3`)
    * `HOMEBREW_TAP_TOKEN`  — only when `homebrew.auth` is `:token`

  When `homebrew.auth` is `:deploy_key`, set up an `ssh-agent` with
  the tap's deploy key before invoking the task (see README).

  ## Flags

    * `--input-dir DIR`  — directory containing release tarballs and
      `.sha256` sidecars (default `"artifacts"`)
    * `--tag VALUE`      — override `GITHUB_REF_NAME`
    * `--dry-run`        — render the formula and print what would be
      pushed (tap, clone URL with tokens redacted, commit message,
      full formula contents) without touching the tap repo
  """

  use Mix.Task

  alias Tinfoil.{Config, Homebrew}

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

    if not config.homebrew.enabled do
      Mix.raise("tinfoil :homebrew is not enabled; set :enabled and :tap in mix.exs")
    end

    case Homebrew.publish(config, Keyword.new(opts)) do
      {:ok, %{dry_run: true} = preview} ->
        report_preview(preview)

      {:ok, %{pushed: false}} ->
        Mix.shell().info("formula unchanged; nothing to push")

      {:ok, %{pushed: true, commit_sha: sha}} ->
        Mix.shell().info([
          :green,
          "* pushed #{config.app} #{config.version} to #{config.homebrew.tap} (",
          String.slice(sha, 0, 7),
          ")",
          :reset
        ])

      {:error, reason} ->
        Mix.raise("homebrew publish failed: #{inspect(reason)}")
    end
  end

  defp report_preview(preview) do
    Mix.shell().info([:cyan, "tinfoil homebrew (dry-run)\n", :reset])
    Mix.shell().info("  tap:            #{preview.tap}")
    Mix.shell().info("  auth:           #{preview.auth}")
    Mix.shell().info("  clone url:      #{preview.clone_url}")
    Mix.shell().info("  formula name:   #{preview.formula_name}")
    Mix.shell().info("  commit message: #{preview.commit_message}")
    Mix.shell().info("\n  formula:")
    preview.formula |> String.split("\n") |> Enum.each(&Mix.shell().info("    " <> &1))
    Mix.shell().info("\n  no git clone, commit, or push performed")
  end
end
