defmodule Mix.Tasks.Tinfoil.Publish do
  @shortdoc "Create a GitHub Release and upload archive assets to it"

  @moduledoc """
  Create a GitHub Release for the current tag and upload every
  archive and checksum file found under the input directory.

  Designed to run on a single CI runner after all matrix builds
  finish and archives are downloaded into one place. The generated
  workflow calls it this way:

      - name: Publish
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: mix tinfoil.publish --input-dir artifacts

  ## Auth

  Requires `GITHUB_TOKEN` (GitHub Actions provides this automatically)
  with `contents: write` permission on the target repository.

  ## Flags

    * `--input-dir` — directory containing archives + sidecars
                      (default `artifacts`)
    * `--tag`       — the release tag, e.g. `v1.2.3`. Defaults to
                      `GITHUB_REF_NAME`, which CI sets for tag pushes.
    * `--draft`     — create the release as a draft
    * `--replace`   — if a release for this tag already exists,
                      delete it (and its assets) and create a fresh
                      one. The git tag itself is untouched. Intended
                      for development / force-retag iteration loops,
                      not for released versions.

  Pre-release detection is automatic: tags containing `-rc`, `-beta`,
  or `-alpha` are marked as prerelease in the created release.
  """

  use Mix.Task

  alias Tinfoil.{Config, Publish}

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [
          input_dir: :string,
          tag: :string,
          draft: :boolean,
          replace: :boolean
        ]
      )

    config =
      case Config.load(Mix.Project.config()) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("tinfoil config error: #{inspect(reason)}")
      end

    case Publish.publish(config, Keyword.take(opts, [:input_dir, :tag, :draft, :replace])) do
      {:ok, result} ->
        report(result)

      {:error, reason} ->
        Mix.raise("tinfoil publish failed: #{format_error(reason)}")
    end
  end

  defp report(result) do
    Mix.shell().info([
      :green,
      "* created release ",
      :reset,
      result.html_url,
      "\n",
      :green,
      "* uploaded ",
      :reset,
      "#{length(result.uploaded)} assets"
    ])

    Enum.each(result.uploaded, fn name ->
      Mix.shell().info([:green, "  - ", :reset, name])
    end)
  end

  defp format_error(:missing_github_token),
    do: "GITHUB_TOKEN (or GH_TOKEN) environment variable is not set"

  defp format_error(:missing_tag),
    do: "no tag given (--tag) and GITHUB_REF_NAME is not set"

  defp format_error({:missing_input_dir, dir}),
    do: "input directory #{inspect(dir)} does not exist"

  defp format_error({:create_release_failed, status, body}),
    do: "GitHub refused to create the release (HTTP #{status}): #{inspect(body)}"

  defp format_error(:release_already_exists_no_replace),
    do:
      "a release for this tag already exists on GitHub. " <>
        "Re-run with --replace to delete and recreate it, or push a new tag."

  defp format_error({:find_release_failed, status, body}),
    do:
      "couldn't look up the existing release for replacement (HTTP #{status}): " <>
        inspect(body)

  defp format_error({:delete_release_failed, status, body}),
    do:
      "couldn't delete the existing release during --replace (HTTP #{status}): " <>
        inspect(body)

  defp format_error({:upload_failed, name, status, body}),
    do: "upload of #{name} failed (HTTP #{status}): #{inspect(body)}"

  defp format_error(other), do: inspect(other)
end
