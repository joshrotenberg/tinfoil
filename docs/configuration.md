# Configuration reference

Every option in the `:tinfoil` keyword of `project/0` in `mix.exs`.
The only required key is `:targets`; everything else has a sensible
default.

```elixir
tinfoil: [
  # Required. Targets to build.
  targets: [:darwin_arm64, :linux_x86_64],

  # Optional: user-defined targets merged on top of the built-in
  # matrix. Each entry needs the full spec shape.
  extra_targets: %{},

  # Optional: collapse every target in an OS family onto one CI
  # runner that builds them sequentially. Defaults to false -- one
  # job per target.
  single_runner_per_os: false,

  # Regex matched against the git tag to auto-mark a release as
  # prerelease. Default covers -rc / -beta / -alpha; override if you
  # use different conventions. See the caveat about Homebrew / Scoop
  # skip logic under "Release channels" in the distribution guide.
  prerelease_pattern: ~r/-(rc|beta|alpha)(\.|$)/,

  # Archive naming template. Interpolations: {app}, {version}, {target}.
  archive_name: "{app}-{version}-{target}",
  archive_format: :tar_gz,

  # GitHub Release configuration. :repo is inferred from
  # `git remote get-url origin` if omitted.
  github: [
    repo: "owner/my_cli",
    draft: false
  ],

  # Homebrew formula generation. Requires auth material for the tap
  # repo -- either HOMEBREW_TAP_TOKEN (PAT) or an SSH deploy key.
  homebrew: [
    enabled: true,
    tap: "owner/homebrew-tap",
    formula_name: "my_cli",                      # defaults to the app name
    auth: :token,                                # or :deploy_key (default :token)
    token_secret: "HOMEBREW_TAP_TOKEN",          # GitHub secret name for the PAT
    deploy_key_secret: "HOMEBREW_TAP_DEPLOY_KEY" # GitHub secret name for the SSH key
  ],

  # Scoop manifest generation (Windows). Same auth model as Homebrew.
  # Requires :windows_x86_64 in :targets.
  scoop: [
    enabled: true,
    bucket: "owner/scoop-bucket",
    manifest_name: "my_cli",                    # defaults to the app name
    auth: :token,                               # or :deploy_key (default :token)
    token_secret: "SCOOP_BUCKET_TOKEN",         # GitHub secret name for the PAT
    deploy_key_secret: "SCOOP_BUCKET_DEPLOY_KEY"
  ],

  # Shell installer script.
  installer: [
    enabled: true,
    install_dir: "~/.local/bin"
  ],

  checksums: :sha256,

  # GitHub build provenance attestations on every uploaded artifact.
  # Defaults to true; set false to opt out (which also drops the
  # `id-token: write` and `attestations: write` permissions from the
  # generated workflow).
  attestations: true,

  # Extra files to bundle alongside the binary in every archive.
  # Bare strings use the same relative path inside the archive; a
  # source/dest map places the file at a custom location.
  extra_artifacts: [
    "LICENSE",
    %{source: "man/myapp.1", dest: "share/man/man1/myapp.1"}
  ],

  ci: [
    provider: :github_actions,
    # All three are auto-detected if not set: elixir_version from
    # the project's :elixir requirement, otp_version from
    # System.otp_release(), zig_version from Burrito.get_versions().
    # These are the fallbacks.
    elixir_version: "1.19",
    otp_version: "28",
    zig_version: "0.15.2"
  ]
]
```

## How it's loaded

`Tinfoil.Config.load/1` reads the keyword, validates it, and
auto-detects a handful of values (elixir/OTP/zig versions, GitHub
repo) when they aren't set. Anything invalid returns an error at
plan time rather than at CI time.

## Regenerating after changes

After editing the `:tinfoil` keyword, run:

```sh
mix tinfoil.generate
```

This rewrites `.github/workflows/release.yml` and any enabled
installer / formula / manifest templates. Commit the regenerated
files.

Tinfoil version bumps usually don't require regeneration -- the
workflow invokes `mix tinfoil.build` and `mix tinfoil.publish`
directly, so logic changes take effect the next CI run. Regenerate
when the workflow template itself changes between tinfoil versions.
