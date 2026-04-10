# tinfoil

[![CI](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinfoil.svg)](https://hex.pm/packages/tinfoil)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tinfoil)
[![License](https://img.shields.io/hexpm/l/tinfoil.svg)](https://github.com/joshrotenberg/tinfoil/blob/main/LICENSE)

Distribution automation for [Burrito](https://github.com/burrito-elixir/burrito)-based Elixir CLIs.

Be to Burrito what [cargo-dist](https://opensource.axo.dev/cargo-dist/) is to Cargo: a
single tool that takes your `mix release` output to platform binaries in a GitHub
Release, with Homebrew and installer support, in under 30 minutes of setup.

> **Status:** pre-1.0, actively developed. The v0.2 line ships the full
> tool-in-the-loop lifecycle (`mix tinfoil.build` and `mix tinfoil.publish`),
> so the generated CI workflow is a thin shell that calls tinfoil tasks and
> upgrading tinfoil upgrades the pipeline. Expect minor breakage as defaults
> get tightened and target strategies evolve — pin to an exact minor version
> if you need stability.

## The problem

Burrito solves binary packaging. Nobody has solved what comes after:
CI matrix builds, GitHub Releases, checksums, Homebrew formulas, installer
scripts. Every team shipping a Burrito-based CLI (Next LS, lazyasdf, etc.)
hand-rolls the same pipeline. tinfoil is that pipeline, as a Hex package.

## Installation

Add tinfoil to your dependencies alongside Burrito:

```elixir
def deps do
  [
    {:burrito, "~> 1.0"},
    {:tinfoil, "~> 0.2", runtime: false}
  ]
end
```

> **Don't set `only: :dev`.** The generated CI workflow runs
> `MIX_ENV=prod mix tinfoil.build`, so tinfoil must be compiled in the prod
> environment too. `runtime: false` keeps it out of the started applications
> at runtime while still making the mix tasks available during builds.

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
| `mix tinfoil.build`      | Build a single target end-to-end: runs `mix release` with the right `BURRITO_TARGET`, packages the binary into a tar.gz, and writes a sha256 sidecar. Called by the generated CI workflow once per matrix entry. |
| `mix tinfoil.publish`    | Create a GitHub Release from artifacts in `artifacts/` and upload every archive plus a combined `checksums-sha256.txt`. Auto-detects `-rc`/`-beta`/`-alpha` tags as prereleases. Pass `--replace` to delete and recreate if a release for the tag already exists. |

The generated CI workflow is a thin shell that calls `mix tinfoil.build`
and `mix tinfoil.publish`, so upgrading tinfoil automatically upgrades
the pipeline — no need to regenerate on most version bumps.

## How tinfoil talks to your Burrito config

tinfoil has its own abstract target atoms (`:darwin_arm64`, `:linux_x86_64`, …)
but Burrito uses whatever names the user chose in their `releases/0` block.
For example, [woof](https://github.com/joshrotenberg/woof) declares:

```elixir
releases: [
  woof: [
    steps: [:assemble, &Burrito.wrap/1],
    burrito: [
      targets: [
        macos:    [os: :darwin, cpu: :x86_64],
        macos_m1: [os: :darwin, cpu: :aarch64],
        linux:    [os: :linux,  cpu: :x86_64]
      ]
    ]
  ]
]
```

When you ask tinfoil to build `:darwin_arm64`, it reads that block,
matches the `[os:, cpu:]` pair, and drives Burrito with
`BURRITO_TARGET=macos_m1`. Then it looks for the output at
`burrito_out/woof_macos_m1` and packages it as
`woof-0.1.0-aarch64-apple-darwin.tar.gz`. You don't have to mirror
tinfoil's target names in your Burrito config — tinfoil resolves them
at `mix tinfoil.plan` time and errors clearly if a tinfoil target has
no matching Burrito target.

### `mix tinfoil.plan`

Read-only preview of the release plan, including the resolved Burrito
target names:

```sh
$ mix tinfoil.plan
tinfoil plan for woof 0.1.0

  target         burrito   runner         archive
  ─────────────  ────────  ─────────────  ───────────────────────────────────────────
  darwin_arm64   macos_m1  macos-latest   woof-0.1.0-aarch64-apple-darwin.tar.gz
  linux_x86_64   linux     ubuntu-latest  woof-0.1.0-x86_64-unknown-linux-musl.tar.gz

  format:    tar_gz (sha256)
  github:    joshrotenberg/woof (draft: false)
  homebrew:  disabled
  installer: ~/.local/bin
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
| `:darwin_x86_64`| `x86_64-apple-darwin`           | `macos-13` ⚠        |
| `:linux_x86_64` | `x86_64-unknown-linux-musl`     | `ubuntu-latest`     |
| `:linux_arm64`  | `aarch64-unknown-linux-musl`    | `ubuntu-24.04-arm`  |

Triples follow the standard Rust-style convention since that is what
users expect to see in release asset names.

> ⚠ **`:darwin_x86_64` availability is unreliable.** GitHub has been
> retiring the `macos-13` Intel runner label. On many accounts the
> job gets queued and then cancelled with no steps executed. The
> current recommendation is to omit `:darwin_x86_64` from your
> `:targets` list until tinfoil lands a cross-compile-from-ARM
> strategy. Tracking this in the roadmap as a priority item.

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
    # elixir_version is auto-detected from the project's :elixir
    # requirement if not explicitly set; these are the current fallbacks.
    elixir_version: "1.19",
    otp_version: "28",
    zig_version: "0.15.2"
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
