# tinfoil

Distribution automation for [Burrito](https://github.com/burrito-elixir/burrito)-based Elixir CLIs.

Be to Burrito what [cargo-dist](https://opensource.axo.dev/cargo-dist/) is to Cargo: a
single tool that takes your `mix release` output to platform binaries in a GitHub
Release, with Homebrew and installer support, in under 30 minutes of setup.

> **Status:** v0.1 — generate-and-forget. `mix tinfoil.init` scaffolds a
> self-contained GitHub Actions workflow. Later versions will evolve the workflow
> to call `mix tinfoil.*` tasks directly, the way cargo-dist does.

## The problem

Burrito solves binary packaging. Nobody has solved what comes after:
CI matrix builds, GitHub Releases, checksums, Homebrew formulas, installer
scripts. Every team shipping a Burrito-based CLI (Next LS, lazyasdf, etc.)
hand-rolls the same pipeline. tinfoil is that pipeline, as a Hex package.

## Installation

Add tinfoil to your dev dependencies alongside Burrito:

```elixir
def deps do
  [
    {:burrito, "~> 1.0"},
    {:tinfoil, "~> 0.1", only: :dev, runtime: false}
  ]
end
```

Then add a `:tinfoil` key to `project/0` in `mix.exs`:

```elixir
def project do
  [
    app: :my_cli,
    version: "0.1.0",
    # ... standard project config ...
    tinfoil: [
      targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64],
      homebrew: [
        enabled: true,
        tap: "owner/homebrew-tap"
      ],
      installer: [
        enabled: true
      ]
    ]
  ]
end
```

Then run:

```sh
mix deps.get
mix tinfoil.init
```

That generates `.github/workflows/release.yml` and any enabled extras
(installer, Homebrew formula template, tap update script). Commit the
generated files, push a tag like `v0.1.0`, and watch the workflow build
and publish platform binaries to a GitHub Release.

## What you get

```
your-project/
├── .github/workflows/release.yml    ← CI pipeline (always)
├── .tinfoil/formula.rb.eex          ← if homebrew enabled
├── scripts/
│   ├── install.sh                   ← if installer enabled
│   └── update-homebrew.sh           ← if homebrew enabled
└── mix.exs
```

The workflow builds for every configured target in parallel, packages
each binary into a `.tar.gz` with a SHA256 sidecar, creates a GitHub
Release, and (optionally) pushes an updated Homebrew formula to your tap.

## Tasks

| Task                     | Description |
| ------------------------ | ----------- |
| `mix tinfoil.init`       | Interactive scaffold — writes config guidance and generates the workflow. |
| `mix tinfoil.generate`   | Regenerate the workflow and scripts from the current config. Run after editing `:tinfoil` in mix.exs or upgrading tinfoil. |
| `mix tinfoil.plan`       | Show what would be built and released. Supports `--format human` (default), `--format json`, and `--format matrix` for GitHub Actions consumption. |

v0.2+ will add `mix tinfoil.build` and `mix tinfoil.publish`, and evolve the
generated workflow to call these tasks directly.

### `mix tinfoil.plan`

Read-only preview of the release plan:

```sh
$ mix tinfoil.plan
tinfoil plan for my_cli 1.2.3

  target         runner            archive
  ─────────────  ────────────────  ──────────────────────────────────────────────
  darwin_arm64   macos-latest      my_cli-1.2.3-aarch64-apple-darwin.tar.gz
  darwin_x86_64  macos-13          my_cli-1.2.3-x86_64-apple-darwin.tar.gz
  linux_x86_64   ubuntu-latest     my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz
  linux_arm64    ubuntu-24.04-arm  my_cli-1.2.3-aarch64-unknown-linux-musl.tar.gz

  format:    tar_gz (sha256)
  github:    owner/my_cli (draft: false)
  homebrew:  disabled
  installer: disabled
```

For CI consumption, `--format matrix` emits a compact GitHub Actions
matrix fragment:

```yaml
- id: plan
  run: echo "matrix=$(mix tinfoil.plan --format matrix)" >> "$GITHUB_OUTPUT"

build:
  needs: plan
  strategy:
    matrix: ${{ fromJson(needs.plan.outputs.matrix) }}
```

## Supported targets

| Target          | Triple                          | GitHub runner       |
| --------------- | ------------------------------- | ------------------- |
| `:darwin_arm64` | `aarch64-apple-darwin`          | `macos-latest`      |
| `:darwin_x86_64`| `x86_64-apple-darwin`           | `macos-13`          |
| `:linux_x86_64` | `x86_64-unknown-linux-musl`     | `ubuntu-latest`     |
| `:linux_arm64`  | `aarch64-unknown-linux-musl`    | `ubuntu-24.04-arm`  |

Triples follow the standard Rust-style convention since that is what
users expect to see in release asset names.

Windows support is deferred until Burrito's Windows story stabilizes.

## Configuration reference

```elixir
tinfoil: [
  # Required. Targets to build.
  targets: [:darwin_arm64, :linux_x86_64],

  # Archive naming template. Interpolations: {app}, {version}, {target}.
  archive_name: "{app}-{version}-{target}",
  archive_format: :tar_gz,

  # GitHub Release configuration. repo is inferred from `git remote get-url
  # origin` if omitted.
  github: [
    repo: "owner/my_cli",
    draft: false
  ],

  # Homebrew formula generation. Requires a HOMEBREW_TAP_TOKEN secret with
  # repo access to the tap.
  homebrew: [
    enabled: true,
    tap: "owner/homebrew-tap",
    formula_name: "my_cli"  # defaults to the app name
  ],

  # Shell installer script.
  installer: [
    enabled: true,
    install_dir: "~/.local/bin"
  ],

  checksums: :sha256,

  ci: [
    provider: :github_actions,
    elixir_version: "1.18",
    otp_version: "28",
    zig_version: "0.13.0"
  ]
]
```

The only required key is `:targets`. Everything else has a sensible default.

## How it compares

- **Burrito** builds self-contained binaries. tinfoil orchestrates everything
  that happens *around* that build. They're peers, not rivals.
- **cargo-dist** is the architectural inspiration. tinfoil borrows the
  "generate-and-delegate" model and the idea that the intelligence should
  live in the tool, not in hand-rolled YAML.
- **Next LS's release pipeline** is the state of the art for Burrito today —
  bespoke, sophisticated, and impossible to reuse. tinfoil is what "the
  reusable version of that" would look like.

## License

MIT.
