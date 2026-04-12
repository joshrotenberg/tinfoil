# tinfoil

[![CI](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinfoil.svg)](https://hex.pm/packages/tinfoil)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tinfoil)
[![License](https://img.shields.io/hexpm/l/tinfoil.svg)](https://github.com/joshrotenberg/tinfoil/blob/main/LICENSE)

Release automation for [Burrito](https://github.com/burrito-elixir/burrito)-based Elixir CLIs.

Tinfoil reads a `:tinfoil` keyword in your `mix.exs`, generates a
GitHub Actions workflow, and provides `mix` tasks that workflow calls
at CI time to build each target, package the binary as a tar.gz with a
sha256 sidecar, create a GitHub Release, and upload the assets.

> **Status:** pre-1.0. The mix tasks, workflow template, and Hex publish
> loop are all in place and dogfooded against a real Burrito project.
> Defaults and target strategies are still evolving — pin to an exact
> minor version if you need stability.

## Scope

Burrito packages an Elixir application into a single binary. Tinfoil
handles the steps around that: the CI matrix that runs the builds, the
archive + checksum packaging, the GitHub Release creation, and
(optionally) an installer script and a Homebrew formula template.

It does not replace Burrito, and it does not try to handle everything
a release pipeline might ever want — anything beyond creating a
GitHub Release and publishing archives (signing, notarization, custom
distribution channels, etc.) is out of scope.

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

That generates `.github/workflows/release.yml` and, if enabled, an
installer script, a Homebrew formula template, and a tap update
script. Commit the generated files and push a tag like `v0.1.0` to
trigger the workflow.

## Generated files

```
your-project/
├── .github/workflows/release.yml    ← CI pipeline (always)
├── .tinfoil/formula.rb.eex          ← if homebrew enabled
├── scripts/
│   ├── install.sh                   ← if installer enabled
│   └── update-homebrew.sh           ← if homebrew enabled
└── mix.exs
```

The workflow runs a build job per configured target in parallel. Each
job calls `mix tinfoil.build`, which produces one `.tar.gz` with a
sha256 sidecar. A release job then collects the artifacts, calls
`mix tinfoil.publish` to create the GitHub Release, and (if homebrew
is enabled) runs the tap update script.

## Tasks

| Task                     | Description |
| ------------------------ | ----------- |
| `mix tinfoil.init`       | Print a suggested `:tinfoil` config snippet and, if one already exists, generate the workflow and supporting files. |
| `mix tinfoil.generate`   | Regenerate the workflow and scripts from the current config. Run after editing `:tinfoil` in mix.exs or upgrading tinfoil. |
| `mix tinfoil.plan`       | Print what would be built and released. Supports `--format human` (default), `--format json`, and `--format matrix` for GitHub Actions consumption. |
| `mix tinfoil.build`      | Build a single target: run `mix release` with the right `BURRITO_TARGET`, package the binary into a tar.gz, and write a sha256 sidecar. Called by the generated workflow once per matrix entry. |
| `mix tinfoil.publish`    | Create a GitHub Release from artifacts in `artifacts/` and upload every archive plus a combined `checksums-sha256.txt`. Tags containing `-rc`, `-beta`, or `-alpha` are marked as prereleases. Pass `--replace` to delete and recreate if a release for the tag already exists. |

The generated workflow invokes `mix tinfoil.build` and
`mix tinfoil.publish` directly, so tinfoil version bumps usually take
effect the next time the workflow runs without needing to regenerate
the YAML.

## Burrito target resolution

Tinfoil uses its own abstract target atoms (`:darwin_arm64`,
`:linux_x86_64`, …) independent of the names you choose in your
Burrito config. At load time, tinfoil reads your `releases/0` block
and matches each tinfoil target to a Burrito target by `[os:, cpu:]`
pair.

For example, suppose your app declares custom Burrito target names:

```elixir
releases: [
  my_cli: [
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

When tinfoil builds `:darwin_arm64`, it finds the matching Burrito
target (`macos_m1`), runs `mix release` with
`BURRITO_TARGET=macos_m1`, reads the output at
`burrito_out/my_cli_macos_m1`, and packages it as
`my_cli-0.1.0-aarch64-apple-darwin.tar.gz`. If a tinfoil target has no
matching Burrito target, `Tinfoil.Config.load/1` returns an error at
plan time naming the expected `[os:, cpu:]` pair.

### `mix tinfoil.plan`

Read-only preview of the release plan, including the resolved Burrito
target names:

```sh
$ mix tinfoil.plan
tinfoil plan for my_cli 0.1.0

  target         burrito   runner         archive
  ─────────────  ────────  ─────────────  ───────────────────────────────────────────────
  darwin_arm64   macos_m1  macos-latest   my_cli-0.1.0-aarch64-apple-darwin.tar.gz
  linux_x86_64   linux     ubuntu-latest  my_cli-0.1.0-x86_64-unknown-linux-musl.tar.gz

  format:    tar_gz (sha256)
  github:    owner/my_cli (draft: false)
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
| `:darwin_x86_64`| `x86_64-apple-darwin`           | `macos-15-intel`    |
| `:linux_x86_64` | `x86_64-unknown-linux-musl`     | `ubuntu-latest`     |
| `:linux_arm64`  | `aarch64-unknown-linux-musl`    | `ubuntu-24.04-arm`  |

Triples follow the standard Rust-style convention since that is what
users expect to see in release asset names.

> **`:darwin_x86_64` uses `macos-15-intel`**, GitHub's last Intel
> runner label, available until August 2027. After that date, native
> x86_64 macOS runners will no longer exist on GitHub Actions. By then
> the Intel Mac install base will be small enough that dropping the
> target is likely the right call.

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
    # All three are auto-detected if not set: elixir_version from the
    # project's :elixir requirement, otp_version from System.otp_release(),
    # zig_version from Burrito.get_versions(). These are the fallbacks.
    elixir_version: "1.19",
    otp_version: "28",
    zig_version: "0.15.2"
  ]
]
```

The only required key is `:targets`. Everything else has a sensible default.

## Related projects

- [**Burrito**](https://github.com/burrito-elixir/burrito) — builds
  self-contained Elixir binaries. Required peer dependency. Tinfoil
  reads your Burrito target config and drives `mix release` via the
  normal Burrito flow.
- [**cargo-dist**](https://opensource.axo.dev/cargo-dist/) — the
  equivalent tool in the Rust/Cargo ecosystem. Tinfoil borrows the
  architectural pattern of a generated CI workflow that calls back
  into the tool via mix tasks, so upgrading the tool upgrades the
  pipeline.

## License

MIT.
