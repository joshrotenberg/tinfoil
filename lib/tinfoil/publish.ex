defmodule Tinfoil.Publish do
  @moduledoc """
  Create a GitHub Release and upload archive assets to it.

  Tinfoil's own replacement for `softprops/action-gh-release` in the
  generated workflow. It uses [`Req`](https://hex.pm/packages/req) to
  talk to GitHub's REST API directly, so the release lifecycle
  (create → upload assets → handle existing releases) happens inside
  the tool rather than inside CI-specific third-party actions.

  The generated workflow calls this module via `mix tinfoil.publish`
  once, after the build matrix finishes, on a single `ubuntu-latest`
  runner.

  Homebrew formula publishing is intentionally out of scope here — the
  existing `scripts/update-homebrew.sh` still handles that path.
  """

  alias Tinfoil.{Archive, Config}

  @github_api "https://api.github.com"

  # Default request timeouts and retry policy for the GitHub API client.
  # Asset uploads in particular can be 50+ MB on slow CI networks, so the
  # default 15s receive_timeout is too short. retry: :transient retries on
  # 408/429/500/502/503/504 and transport errors across all HTTP methods
  # (including POSTs). The duplicate-POST edge case a retry could cause is
  # already covered by the existing "release already exists" handling and
  # --replace escape hatch.
  @receive_timeout :timer.minutes(5)
  @pool_timeout :timer.seconds(30)

  @type opts :: [
          input_dir: Path.t(),
          tag: String.t() | nil,
          draft: boolean() | nil,
          replace: boolean() | nil,
          req: Req.Request.t() | nil
        ]

  @type result :: %{
          release_id: integer(),
          html_url: String.t(),
          uploaded: [String.t()]
        }

  @doc """
  Publish release archives from `input_dir` (default `"artifacts"`) to
  a new GitHub Release on the repo configured in the tinfoil config.

  The set of assets uploaded is every `*.tar.gz` or `*.zip` in
  `input_dir`, plus the combined `checksums-sha256.txt` produced from
  their `.sha256` sidecars.

  ## Authentication

  Requires a `GITHUB_TOKEN` environment variable (or a `GH_TOKEN`
  fallback) with `contents: write` permission on the target repo.

  ## Tag

  The tag to release against is taken from `opts[:tag]` if given,
  otherwise from the `GITHUB_REF_NAME` environment variable (which
  CI sets automatically on tag pushes). Versions matching `-rc`,
  `-beta`, or `-alpha` are auto-marked as prerelease.

  ## Existing releases

  By default, if a release for `tag` already exists, `publish/2`
  returns `{:error, :release_already_exists_no_replace}` without
  touching the existing release or its assets — failing fast is
  safer than silently clobbering something a user already shipped.

  Pass `replace: true` (or `--replace` on the mix task) to delete
  and recreate the existing release. The git tag itself is never
  touched; only the release object and its attached assets are
  removed before the new release is created. Use this primarily
  for development and force-retag iteration loops, not for published
  versions.
  """
  @spec publish(Config.t(), opts()) :: {:ok, result()} | {:error, term()}
  def publish(%Config{} = config, opts \\ []) do
    # Mix tasks don't auto-start their dep apps' supervision trees. Req
    # owns a built-in Finch pool named Req.Finch that must be running
    # before any request; without this call we crash with
    # `ArgumentError: unknown registry: Req.Finch`.
    {:ok, _} = Application.ensure_all_started(:req)

    input_dir = Keyword.get(opts, :input_dir, "artifacts")

    with {:ok, repo} <- fetch_repo(config),
         {:ok, tag} <- fetch_tag(opts),
         :ok <- ensure_input_dir(input_dir),
         {:ok, req} <- build_req(opts) do
      _combined = Archive.combined_checksums(input_dir)
      assets = list_assets(input_dir)

      with {:ok, release} <- create_or_replace_release(req, repo, tag, config, opts),
           {:ok, uploaded} <- upload_assets(req, release, assets) do
        {:ok,
         %{
           release_id: release["id"],
           html_url: release["html_url"],
           uploaded: uploaded
         }}
      end
    end
  end

  ## ───────────────────── internals ─────────────────────

  defp fetch_repo(%Config{github: %{repo: nil}}),
    do: {:error, ":github :repo is unresolved — set it in :tinfoil config or push a git remote"}

  defp fetch_repo(%Config{github: %{repo: repo}}), do: {:ok, repo}

  defp fetch_token do
    case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
      nil -> {:error, :missing_github_token}
      "" -> {:error, :missing_github_token}
      token -> {:ok, token}
    end
  end

  defp fetch_tag(opts) do
    tag = Keyword.get(opts, :tag) || System.get_env("GITHUB_REF_NAME")

    case tag do
      nil -> {:error, :missing_tag}
      "" -> {:error, :missing_tag}
      tag -> {:ok, tag}
    end
  end

  defp ensure_input_dir(dir) do
    if File.dir?(dir) do
      :ok
    else
      {:error, {:missing_input_dir, dir}}
    end
  end

  defp list_assets(input_dir) do
    archives =
      [Path.join(input_dir, "*.tar.gz"), Path.join(input_dir, "*.zip")]
      |> Enum.flat_map(&Path.wildcard/1)

    checksums = Path.join(input_dir, "checksums-sha256.txt")

    (archives ++ [checksums])
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp build_req(opts) do
    case Keyword.get(opts, :req) do
      %Req.Request{} = req ->
        {:ok, req}

      nil ->
        with {:ok, token} <- fetch_token() do
          {:ok,
           Req.new(
             base_url: @github_api,
             headers: [
               {"accept", "application/vnd.github+json"},
               {"x-github-api-version", "2022-11-28"},
               {"authorization", "Bearer #{token}"},
               {"user-agent", "tinfoil/#{tinfoil_version()}"}
             ],
             receive_timeout: @receive_timeout,
             pool_timeout: @pool_timeout,
             retry: :transient,
             max_retries: 3
           )}
        end
    end
  end

  defp create_or_replace_release(req, repo, tag, config, opts) do
    case create_release(req, repo, tag, config, opts) do
      {:ok, release} ->
        {:ok, release}

      {:error, {:create_release_failed, 422, body}} = err ->
        if release_already_exists?(body) do
          handle_existing_release(req, repo, tag, config, opts)
        else
          err
        end

      other ->
        other
    end
  end

  defp handle_existing_release(req, repo, tag, config, opts) do
    if Keyword.get(opts, :replace, false) do
      with {:ok, existing} <- find_release_by_tag(req, repo, tag),
           :ok <- delete_release(req, repo, existing["id"]) do
        create_release(req, repo, tag, config, opts)
      end
    else
      {:error, :release_already_exists_no_replace}
    end
  end

  defp release_already_exists?(%{"errors" => errors}) when is_list(errors) do
    Enum.any?(errors, fn err ->
      is_map(err) and err["code"] == "already_exists" and err["field"] == "tag_name"
    end)
  end

  defp release_already_exists?(_), do: false

  defp find_release_by_tag(req, repo, tag) do
    case Req.get(req, url: "/repos/#{repo}/releases/tags/#{tag}") do
      {:ok, %Req.Response{status: 200, body: release}} ->
        {:ok, release}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:find_release_failed, status, body}}

      {:error, reason} ->
        {:error, {:find_release_error, reason}}
    end
  end

  defp delete_release(req, repo, id) do
    case Req.delete(req, url: "/repos/#{repo}/releases/#{id}") do
      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:delete_release_failed, status, body}}

      {:error, reason} ->
        {:error, {:delete_release_error, reason}}
    end
  end

  defp create_release(req, repo, tag, config, opts) do
    body = %{
      tag_name: tag,
      name: tag,
      draft: Keyword.get(opts, :draft, config.github[:draft] || false),
      prerelease: prerelease?(tag),
      generate_release_notes: true
    }

    case Req.post(req, url: "/repos/#{repo}/releases", json: body) do
      {:ok, %Req.Response{status: 201, body: release}} ->
        {:ok, release}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:create_release_failed, status, body}}

      {:error, reason} ->
        {:error, {:create_release_error, reason}}
    end
  end

  defp upload_assets(req, release, assets) do
    upload_template = release["upload_url"]

    Enum.reduce_while(assets, {:ok, []}, fn path, {:ok, acc} ->
      case upload_one(req, upload_template, path) do
        {:ok, name} -> {:cont, {:ok, [name | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      other -> other
    end
  end

  # 64KB chunks balance syscall overhead against memory footprint; the body
  # is streamed so a multi-hundred-MB asset never sits in RAM as a single binary.
  @upload_chunk_bytes 64 * 1024

  defp upload_one(req, upload_template, path) do
    name = Path.basename(path)
    upload_url = String.replace(upload_template, ~r/\{\?.*\}/, "")
    size = File.stat!(path).size
    body = File.stream!(path, @upload_chunk_bytes)

    case Req.post(req,
           url: upload_url,
           params: [name: name],
           headers: [
             {"content-type", content_type(path)},
             {"content-length", Integer.to_string(size)}
           ],
           body: body
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, name}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:upload_failed, name, status, body}}

      {:error, reason} ->
        {:error, {:upload_error, name, reason}}
    end
  end

  defp content_type(path) do
    cond do
      String.ends_with?(path, ".tar.gz") -> "application/gzip"
      String.ends_with?(path, ".zip") -> "application/zip"
      String.ends_with?(path, ".txt") -> "text/plain"
      true -> "application/octet-stream"
    end
  end

  @doc false
  def prerelease?(tag) do
    tag =~ ~r/-(rc|beta|alpha)(\.|$)/
  end

  defp tinfoil_version do
    case Application.spec(:tinfoil, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end
end
