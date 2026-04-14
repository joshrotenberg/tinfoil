defmodule Tinfoil.Scoop do
  @moduledoc """
  Render a Scoop manifest from release artifacts and push it to a
  bucket repo. The Windows-package-manager counterpart to
  `Tinfoil.Homebrew`, same shape: mix task at CI time, token or
  deploy-key auth, dry-run preview.

  Scoop's manifest is a JSON document keyed by architecture rather
  than a Ruby DSL, so unlike Homebrew there is no user-facing
  `.eex` template shipped into the user's repo -- tinfoil owns the
  manifest layout end-to-end. If you need to customize beyond the
  schema, override the rendered file in a post-publish step or open
  an issue.

  Requires the `:windows_x86_64` target to be in your `:tinfoil
  :targets` list (or Scoop has nothing to point at).
  """

  alias Tinfoil.Config

  @default_author_name "tinfoil-bot"
  @default_author_email "tinfoil-bot@users.noreply.github.com"

  @type opts :: [
          input_dir: Path.t(),
          tag: String.t() | nil,
          bucket_dir: Path.t() | nil,
          dry_run: boolean() | nil,
          git: module()
        ]

  @type result :: %{
          pushed: boolean(),
          manifest_path: Path.t(),
          commit_sha: String.t() | nil
        }

  @type preview :: %{
          dry_run: true,
          bucket: String.t(),
          auth: :token | :deploy_key,
          clone_url: String.t(),
          manifest_name: String.t(),
          manifest: String.t(),
          commit_message: String.t()
        }

  @typedoc """
  Known error atoms returned by `publish/2`.

    * `:scoop_not_enabled` -- config has `scoop.enabled: false`
    * `:missing_tag` -- no tag and `GITHUB_REF_NAME` is unset
    * `:missing_scoop_bucket_token` -- `auth: :token` but
      `SCOOP_BUCKET_TOKEN` (or the configured token_secret) is missing
    * `:missing_windows_target` -- windows_x86_64 isn't in :targets,
      so there's nothing to publish
    * `{:missing_sha_sidecar, target, path}` -- the sha sidecar for
      the windows archive wasn't found in `input_dir`
    * `:malformed_sha_sidecar`
    * `{:git_failed, args, exit_status, output}`
  """
  @type error ::
          :scoop_not_enabled
          | :missing_tag
          | :missing_scoop_bucket_token
          | :missing_windows_target
          | :malformed_sha_sidecar
          | {:missing_sha_sidecar, atom(), Path.t()}
          | {:git_failed, [String.t()], non_neg_integer(), String.t()}

  @spec publish(Config.t(), opts()) ::
          {:ok, result()} | {:ok, preview()} | {:error, error() | term()}
  def publish(config, opts \\ [])

  def publish(%Config{scoop: %{enabled: false}}, _opts), do: {:error, :scoop_not_enabled}

  def publish(%Config{} = config, opts) do
    cond do
      :windows_x86_64 not in config.targets ->
        {:error, :missing_windows_target}

      Keyword.get(opts, :dry_run, false) ->
        dry_run(config, opts)

      true ->
        do_publish(config, opts)
    end
  end

  defp do_publish(config, opts) do
    git = Keyword.get(opts, :git, Tinfoil.Homebrew.Git)
    input_dir = Keyword.get(opts, :input_dir, "artifacts")

    with {:ok, tag} <- fetch_tag(opts),
         version = String.trim_leading(tag, "v"),
         {:ok, sha} <- read_windows_sha(input_dir, config),
         {:ok, manifest} <- render_manifest(config, version, sha),
         {:ok, bucket_dir} <- ensure_bucket_dir(opts),
         {:ok, clone_url} <- build_clone_url(config.scoop),
         :ok <- git.clone(clone_url, bucket_dir),
         manifest_path = Path.join(bucket_dir, "#{config.scoop.manifest_name}.json"),
         :ok <- write_manifest(manifest_path, manifest),
         :ok <- git.config_identity(bucket_dir, @default_author_name, @default_author_email),
         {:ok, commit_sha} <-
           maybe_commit_and_push(git, bucket_dir, manifest_path, config, version) do
      {:ok, %{pushed: commit_sha != nil, manifest_path: manifest_path, commit_sha: commit_sha}}
    end
  end

  # Render everything real `publish/2` would send, without cloning.
  # Token is redacted in the preview's clone URL.
  defp dry_run(config, opts) do
    input_dir = Keyword.get(opts, :input_dir, "artifacts")

    with {:ok, tag} <- fetch_tag(opts),
         version = String.trim_leading(tag, "v"),
         {:ok, sha} <- read_windows_sha(input_dir, config),
         {:ok, manifest} <- render_manifest(config, version, sha),
         {:ok, clone_url} <- build_clone_url(config.scoop) do
      {:ok,
       %{
         dry_run: true,
         bucket: config.scoop.bucket,
         auth: config.scoop.auth,
         clone_url: redact_url(clone_url),
         manifest_name: "#{config.scoop.manifest_name}.json",
         manifest: manifest,
         commit_message: "#{config.app} #{version}"
       }}
    end
  end

  ## ───────────────────── internals ─────────────────────

  defp fetch_tag(opts) do
    tag = Keyword.get(opts, :tag) || System.get_env("GITHUB_REF_NAME")

    case tag do
      nil -> {:error, :missing_tag}
      "" -> {:error, :missing_tag}
      tag -> {:ok, tag}
    end
  end

  defp read_windows_sha(input_dir, config) do
    archive = Config.archive_filename(config, :windows_x86_64)
    sha_path = Path.join(input_dir, archive <> ".sha256")

    case File.read(sha_path) do
      {:ok, contents} -> parse_sha_sidecar(contents)
      {:error, _} -> {:error, {:missing_sha_sidecar, :windows_x86_64, sha_path}}
    end
  end

  defp parse_sha_sidecar(contents) do
    case contents |> String.trim() |> String.split(~r/\s+/, parts: 2) do
      [sha | _] when byte_size(sha) == 64 -> {:ok, sha}
      _ -> {:error, :malformed_sha_sidecar}
    end
  end

  defp render_manifest(config, version, sha_windows_x86_64) do
    repo = config.github.repo || "OWNER/REPO"

    assigns = [
      app: config.app,
      version: version,
      description: config.description || "#{config.app} CLI",
      homepage: config.homepage_url || "https://github.com/#{repo}",
      license: config.license || "MIT",
      base_url: "https://github.com/#{repo}/releases",
      sha_windows_x86_64: sha_windows_x86_64
    ]

    {:ok, Tinfoil.Generator.render_scoop(assigns)}
  end

  defp ensure_bucket_dir(opts) do
    case Keyword.get(opts, :bucket_dir) do
      nil ->
        tmp = Path.join(System.tmp_dir!(), "tinfoil-bucket-#{System.unique_integer([:positive])}")
        File.mkdir_p!(tmp)
        {:ok, tmp}

      path ->
        File.mkdir_p!(path)
        {:ok, path}
    end
  end

  defp build_clone_url(%{bucket: bucket, auth: :token, token_secret: secret_name}) do
    case System.get_env(env_name_for_token(secret_name)) do
      nil -> {:error, :missing_scoop_bucket_token}
      "" -> {:error, :missing_scoop_bucket_token}
      token -> {:ok, "https://x-access-token:#{token}@github.com/#{bucket}.git"}
    end
  end

  defp build_clone_url(%{bucket: bucket, auth: :deploy_key}) do
    {:ok, "git@github.com:#{bucket}.git"}
  end

  # The mix task reads SCOOP_BUCKET_TOKEN at runtime regardless of what
  # the workflow secret is called -- `token_secret` only controls the
  # workflow-side mapping, not the env var name here. Keeping this
  # helper in case we ever want to loosen that.
  defp env_name_for_token(_configured), do: "SCOOP_BUCKET_TOKEN"

  defp write_manifest(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
    :ok
  end

  defp maybe_commit_and_push(git, bucket_dir, manifest_path, config, version) do
    relative = Path.relative_to(manifest_path, bucket_dir)
    :ok = git.add(bucket_dir, relative)

    case git.staged_changes?(bucket_dir) do
      false ->
        {:ok, nil}

      true ->
        message = "#{config.app} #{version}"

        with {:ok, sha} <- git.commit(bucket_dir, message),
             :ok <- git.push(bucket_dir) do
          {:ok, sha}
        end
    end
  end

  defp redact_url("https://x-access-token:" <> rest) do
    case String.split(rest, "@", parts: 2) do
      [_token, tail] -> "https://x-access-token:****@" <> tail
      _ -> "https://x-access-token:****"
    end
  end

  defp redact_url(url), do: url
end
