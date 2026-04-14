defmodule Tinfoil.Homebrew do
  @moduledoc """
  Render a Homebrew formula from release artifacts and push it to a
  tap repo. Earlier tinfoil versions shelled out to a generated
  `scripts/update-homebrew.sh`; this module replaces it so the whole
  release lifecycle stays in Elixir and is unit-testable.

  Called from `mix tinfoil.homebrew`, which the generated workflow
  invokes on a separate CI job after the GitHub Release publish step
  succeeds. See `Tinfoil.Publish` for the release-assets counterpart.

  ## Inputs at CI time

    * `artifacts/` directory containing the release tarballs plus
      `.sha256` sidecar files (downloaded from the build matrix)
    * `GITHUB_REF_NAME` env var holding the tag that triggered the
      release (e.g. `v1.2.3`)
    * Auth material depending on `config.homebrew.auth`:
      * `:token`      — `HOMEBREW_TAP_TOKEN` env with PAT
      * `:deploy_key` — SSH agent configured with a deploy key for
        the tap repo (typically via `webfactory/ssh-agent`)

  ## What the module does

  1. Reads `.sha256` sidecars for every target's archive and builds a
     map of `target => sha256`.
  2. Renders the user's checked-in `.tinfoil/formula.rb.eex` (falling
     back to the default template) with real version + SHAs.
  3. Clones the tap repo into a temp dir, writes the rendered formula
     at `Formula/<formula_name>.rb`, commits and pushes.

  The git operations shell out to `git` — no extra deps. Authentication
  is left to the environment: HTTPS with a token-bearing URL, or SSH
  via an already-running `ssh-agent`.
  """

  alias Tinfoil.Config

  @default_author_name "tinfoil-bot"
  @default_author_email "tinfoil-bot@users.noreply.github.com"

  @type opts :: [
          input_dir: Path.t(),
          tag: String.t() | nil,
          formula_template: Path.t() | nil,
          tap_dir: Path.t() | nil,
          dry_run: boolean() | nil,
          git: module()
        ]

  @type result :: %{
          pushed: boolean(),
          formula_path: Path.t(),
          commit_sha: String.t() | nil
        }

  @type preview :: %{
          dry_run: true,
          tap: String.t(),
          auth: :token | :deploy_key,
          clone_url: String.t(),
          formula_name: String.t(),
          formula: String.t(),
          commit_message: String.t()
        }

  @doc """
  Render the formula and push it to the tap repo.

  Options (all optional, sane defaults):

    * `:input_dir`        — directory with archives + sha256 sidecars
      (default `"artifacts"`)
    * `:tag`              — release tag, usually taken from
      `GITHUB_REF_NAME` env
    * `:formula_template` — path to the EEx formula template
      (default `".tinfoil/formula.rb.eex"`)
    * `:tap_dir`          — temp dir to clone into (default a new mktemp)
    * `:git`              — module implementing the `git` callbacks
      (see `Tinfoil.Homebrew.Git`); injected for testing
  """
  @spec publish(Config.t(), opts()) ::
          {:ok, result()} | {:ok, preview()} | {:error, term()}
  def publish(config, opts \\ [])

  def publish(%Config{homebrew: %{enabled: false}}, _opts),
    do: {:error, :homebrew_not_enabled}

  def publish(%Config{} = config, opts) do
    if Keyword.get(opts, :dry_run, false) do
      dry_run(config, opts)
    else
      do_publish(config, opts)
    end
  end

  defp do_publish(config, opts) do
    git = Keyword.get(opts, :git, Tinfoil.Homebrew.Git)
    input_dir = Keyword.get(opts, :input_dir, "artifacts")
    template_path = Keyword.get(opts, :formula_template, ".tinfoil/formula.rb.eex")

    with {:ok, tag} <- fetch_tag(opts),
         version = String.trim_leading(tag, "v"),
         {:ok, shas} <- collect_shas(input_dir, config),
         {:ok, template} <- read_template(template_path),
         {:ok, formula} <- render_formula(template, version, shas),
         {:ok, tap_dir} <- ensure_tap_dir(opts),
         {:ok, clone_url} <- build_clone_url(config.homebrew),
         :ok <- git.clone(clone_url, tap_dir),
         formula_path = Path.join([tap_dir, "Formula", "#{config.homebrew.formula_name}.rb"]),
         :ok <- write_formula(formula_path, formula),
         :ok <- git.config_identity(tap_dir, @default_author_name, @default_author_email),
         {:ok, commit_sha} <- maybe_commit_and_push(git, tap_dir, formula_path, config, version) do
      {:ok, %{pushed: commit_sha != nil, formula_path: formula_path, commit_sha: commit_sha}}
    end
  end

  # Render everything real `publish/2` would send, without cloning,
  # committing, or pushing. Still reads the artifacts + template from
  # disk because that's how we know the rendered formula is valid.
  # The clone URL redacts any token baked into the auth URL.
  defp dry_run(config, opts) do
    input_dir = Keyword.get(opts, :input_dir, "artifacts")
    template_path = Keyword.get(opts, :formula_template, ".tinfoil/formula.rb.eex")

    with {:ok, tag} <- fetch_tag(opts),
         version = String.trim_leading(tag, "v"),
         {:ok, shas} <- collect_shas(input_dir, config),
         {:ok, template} <- read_template(template_path),
         {:ok, formula} <- render_formula(template, version, shas),
         {:ok, clone_url} <- build_clone_url(config.homebrew) do
      {:ok,
       %{
         dry_run: true,
         tap: config.homebrew.tap,
         auth: config.homebrew.auth,
         clone_url: redact_url(clone_url),
         formula_name: "#{config.homebrew.formula_name}.rb",
         formula: formula,
         commit_message: "#{config.app} #{version}"
       }}
    end
  end

  # Strip a token baked into an HTTPS clone URL before showing it back
  # to the user. `git@` URLs don't carry secrets so they pass through.
  defp redact_url("https://x-access-token:" <> rest) do
    case String.split(rest, "@", parts: 2) do
      [_token, tail] -> "https://x-access-token:****@" <> tail
      _ -> "https://x-access-token:****"
    end
  end

  defp redact_url(url), do: url

  ## ───────────────────── internals ─────────────────────

  defp fetch_tag(opts) do
    tag = Keyword.get(opts, :tag) || System.get_env("GITHUB_REF_NAME")

    case tag do
      nil -> {:error, :missing_tag}
      "" -> {:error, :missing_tag}
      tag -> {:ok, tag}
    end
  end

  # Walk the user's targets, look up each target's archive filename, read
  # the sha256 sidecar, and return %{target => sha}. Missing sidecars are
  # a hard error — we can't render a Homebrew formula with blank shas.
  defp collect_shas(input_dir, config) do
    Enum.reduce_while(config.targets, {:ok, %{}}, fn target, {:ok, acc} ->
      case read_target_sha(input_dir, config, target) do
        {:ok, sha} -> {:cont, {:ok, Map.put(acc, target, sha)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp read_target_sha(input_dir, config, target) do
    archive = Config.archive_filename(config, target)
    sha_path = Path.join(input_dir, archive <> ".sha256")

    case File.read(sha_path) do
      {:ok, contents} -> parse_sha_sidecar(contents)
      {:error, _} -> {:error, {:missing_sha_sidecar, target, sha_path}}
    end
  end

  defp parse_sha_sidecar(contents) do
    case contents |> String.trim() |> String.split(~r/\s+/, parts: 2) do
      [sha | _] when byte_size(sha) == 64 -> {:ok, sha}
      _ -> {:error, :malformed_sha_sidecar}
    end
  end

  defp read_template(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, :enoent} ->
        {:error, {:missing_formula_template, path}}

      {:error, reason} ->
        {:error, {:formula_template_read_error, path, reason}}
    end
  end

  # The committed template contains __VERSION__ and __SHA256_<TARGET>__
  # placeholders; substitute them with the real values. Using string
  # replace instead of EEx keeps the template committable and readable
  # for humans who want to customize it manually.
  defp render_formula(template, version, shas) do
    rendered =
      shas
      |> Enum.reduce(template, fn {target, sha}, acc ->
        String.replace(acc, placeholder(target), sha)
      end)
      |> String.replace("__VERSION__", version)

    {:ok, rendered}
  end

  # :darwin_arm64 -> "__SHA256_DARWIN_ARM64__"
  defp placeholder(target) do
    "__SHA256_" <> String.upcase(to_string(target)) <> "__"
  end

  defp ensure_tap_dir(opts) do
    case Keyword.get(opts, :tap_dir) do
      nil ->
        tmp = Path.join(System.tmp_dir!(), "tinfoil-tap-#{System.unique_integer([:positive])}")
        File.mkdir_p!(tmp)
        {:ok, tmp}

      path ->
        File.mkdir_p!(path)
        {:ok, path}
    end
  end

  # Token auth uses an HTTPS URL with an x-access-token credential
  # baked into it; deploy-key auth uses the SSH clone URL and expects
  # an ssh-agent with the private key already loaded.
  defp build_clone_url(%{tap: tap, auth: :token}) do
    case System.get_env("HOMEBREW_TAP_TOKEN") do
      nil -> {:error, :missing_homebrew_tap_token}
      "" -> {:error, :missing_homebrew_tap_token}
      token -> {:ok, "https://x-access-token:#{token}@github.com/#{tap}.git"}
    end
  end

  defp build_clone_url(%{tap: tap, auth: :deploy_key}) do
    {:ok, "git@github.com:#{tap}.git"}
  end

  defp write_formula(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
    :ok
  end

  defp maybe_commit_and_push(git, tap_dir, formula_path, config, version) do
    relative = Path.relative_to(formula_path, tap_dir)
    :ok = git.add(tap_dir, relative)

    case git.staged_changes?(tap_dir) do
      false ->
        {:ok, nil}

      true ->
        message = "#{config.app} #{version}"

        with {:ok, sha} <- git.commit(tap_dir, message),
             :ok <- git.push(tap_dir) do
          {:ok, sha}
        end
    end
  end
end
