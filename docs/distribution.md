# Distribution

A tagged push produces a GitHub Release with every built archive
attached plus a combined `checksums-sha256.txt`. Optional surfaces
layered on top: a curl/PowerShell installer, a Homebrew formula, a
Scoop manifest. All configured in the `:tinfoil` keyword.

## GitHub Release

Generated unconditionally. `mix tinfoil.publish` creates the
release, attaches every archive, and adds `checksums-sha256.txt`.
Tags matching `prerelease_pattern` (default: `-rc`, `-beta`,
`-alpha`) are marked as prereleases.

## Installer scripts

Set `installer: [enabled: true]` to ship two scripts with every
release:

- `scripts/install.sh` -- `curl | sh` for Unix.
- `scripts/install.ps1` -- `iex (irm ...)` for Windows.

Both resolve the latest release tag from the GitHub API, download
the right asset for the detected OS/arch, verify it against the
combined `checksums-sha256.txt`, and install to a sensible default
directory (configurable via flags at install time).

Configure the default destination:

```elixir
installer: [
  enabled: true,
  install_dir: "~/.local/bin"
]
```

## Extra files in every archive

`extra_artifacts:` ships additional files alongside the binary
inside each archive. Bare strings use the same relative path; a
`source/dest` map places the file at a custom location:

```elixir
extra_artifacts: [
  "LICENSE",
  %{source: "man/myapp.1", dest: "share/man/man1/myapp.1"}
]
```

Useful for LICENSE, man pages, shell completions, or anything else
a user might expect in a distribution tarball.

## Homebrew

The `homebrew:` job needs push access to your tap repo. Two auth
modes are supported.

### `auth: :token` (default)

The workflow expects a `HOMEBREW_TAP_TOKEN` repo secret -- a
Personal Access Token (classic or fine-grained) with
`contents: write` on the tap repo. The mix task clones over HTTPS
with the token baked into the URL.

```elixir
homebrew: [
  enabled: true,
  tap: "owner/homebrew-tap"
]
```

### `auth: :deploy_key`

Generate an SSH key pair, add the public key to the tap repo's
deploy keys (with write access), and set the private key as the
`HOMEBREW_TAP_DEPLOY_KEY` secret on the CLI repo. The generated
workflow installs
[`webfactory/ssh-agent`](https://github.com/webfactory/ssh-agent)
before running `mix tinfoil.homebrew`, which clones over SSH.

```elixir
homebrew: [
  enabled: true,
  tap: "owner/homebrew-tap",
  auth: :deploy_key
]
```

Deploy keys are scoped to a single repo and never expire, which is
the main reason to prefer them over PATs.

### Secret name overrides

If your secret is named differently, override the name with
`homebrew: [token_secret: "YOUR_NAME"]` or
`homebrew: [deploy_key_secret: "YOUR_NAME"]`. The env var the mix
task reads is fixed; only the secret reference in the workflow is
configurable.

### Linuxbrew

The generated formula's `on_linux` block makes it work under
[Linuxbrew](https://docs.brew.sh/Homebrew-on-Linux) too, no
separate config needed. Linux users can run
`brew install owner/tap/myapp` the same way macOS users do and will
pull the matching `linux_x86_64` or `linux_arm64` tarball.

## Scoop (Windows)

Symmetric counterpart to Homebrew for Windows users. When
`scoop: [enabled: true]` and you have `:windows_x86_64` in
`:targets`, every release pushes a Scoop manifest to the configured
bucket repo:

```elixir
scoop: [
  enabled: true,
  bucket: "owner/scoop-bucket",
  auth: :token  # or :deploy_key
]
```

Create the bucket repo on GitHub (any name works; the convention is
`scoop-<something>`), grant push access via a PAT named
`SCOOP_BUCKET_TOKEN` or an SSH deploy key named
`SCOOP_BUCKET_DEPLOY_KEY`, and downstream users install with:

```sh
scoop bucket add owner https://github.com/owner/scoop-bucket
scoop install owner/my_cli
```

The rendered manifest includes a `checkver` + `autoupdate` block
so Scoop bucket maintainers (or automated bots) can pick up new
versions without tinfoil re-pushing. If you don't want that, edit
the manifest in the bucket after push.

Secret name overrides work the same way as Homebrew via
`scoop: [token_secret: "..."]` / `[deploy_key_secret: "..."]`.

## Release channels and prerelease handling

`prerelease_pattern` controls two things:

- **GitHub Release creation** (`mix tinfoil.publish`) -- the
  release is marked as a prerelease when the tag matches.
- **Homebrew / Scoop push-skip** -- the generated workflow jobs
  skip the publish step when the tag looks like a prerelease, so
  tagged prereleases don't overwrite the stable formula/manifest.

The workflow's skip condition is hardcoded to match the default
pattern (`-rc`, `-beta`, `-alpha`). If you override
`prerelease_pattern` to use different tokens (`-dev`, `-nightly`,
`-snapshot`, ...), `mix tinfoil.publish` will respect your pattern
for the release flag, but the Homebrew and Scoop jobs will still
only skip the default tokens. Workarounds:

- Keep a superset pattern in `prerelease_pattern` that always
  includes the default tokens, or
- Add a `homebrew: [enabled: false]` / `scoop: [enabled: false]`
  environment-gated override (the release still gets published;
  the package managers just won't auto-update), or
- Hand-edit `.github/workflows/release.yml` after
  `mix tinfoil.generate` to extend the `if:` expression.

Unifying this into a single configurable skip list is tracked;
open a PR if you need it before we get there.

## Attestations

Every uploaded artifact is attested by GitHub Actions build
provenance by default (`attestations: true`). End users can verify
with:

```sh
gh attestation verify my_cli-0.1.0-aarch64-apple-darwin.tar.gz \
  --repo owner/my_cli
```

Opting out (`attestations: false`) drops the `id-token: write` and
`attestations: write` permissions from the generated workflow.
