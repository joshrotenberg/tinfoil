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
  """

  use Mix.Task

  alias Tinfoil.{Config, Homebrew}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [input_dir: :string, tag: :string],
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
end
