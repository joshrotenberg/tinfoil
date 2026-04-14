# tinfoil

[![CI](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinfoil.svg)](https://hex.pm/packages/tinfoil)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tinfoil)
[![License](https://img.shields.io/hexpm/l/tinfoil.svg)](https://github.com/joshrotenberg/tinfoil/blob/main/LICENSE)

Release automation for [Burrito](https://github.com/burrito-elixir/burrito)-based Elixir CLIs. Tag a version, tinfoil ships the binaries.

## What you get

One `git tag v1.0.0 && git push --tags` produces:

- **Cross-compiled binaries** for darwin (arm64, x86_64), linux
  (arm64, x86_64 musl), and windows (x86_64) — built on GitHub
  Actions, cross-compiled via Zig (no native ARM or Windows runner
  required).
- **A GitHub Release** with every archive attached, a combined
  `checksums-sha256.txt`, and release notes auto-generated from
  your commits.
- **A `curl | sh` installer** (optional) at `scripts/install.sh` and
  a PowerShell equivalent at `scripts/install.ps1`. Both pick the
  right asset for the user's OS/arch and verify the sha256 before
  installing.
- **An updated Homebrew formula** (optional) pushed to your tap so
  `brew install you/tap/yourcli` just works — tinfoil renders
  `Formula/yourcli.rb` with real URLs + SHAs and commits it, under
  either a PAT or an SSH deploy key.
- **A regeneratable workflow.** `mix tinfoil.generate` rewrites
  `.github/workflows/release.yml` from your `mix.exs` config, so
  upgrading tinfoil upgrades the pipeline.

All configured via one `:tinfoil` keyword in `mix.exs`; no hand-edited
YAML. See [tinfoil_demo](https://github.com/joshrotenberg/tinfoil_demo)
for a full working project.

> **Status:** pre-1.0. The mix tasks, workflow template, and Hex
> publish loop are all in place and dogfooded against a real Burrito
> project. Defaults and target strategies are still evolving — pin
> to an exact minor version if you need stability.

## How it works

Tinfoil reads the `:tinfoil` keyword in `mix.exs`, resolves it
against your Burrito `:releases` config, and provides `mix` tasks
the generated workflow calls at CI time. The workflow runs one
build job per target (or one per OS family if you opt into
`single_runner_per_os`), uploads artifacts, and a release job
stitches them into a GitHub Release plus (optionally) a Homebrew
tap push.

## Scope

Burrito packages an Elixir application into a single binary.
Tinfoil handles the steps around that: the CI matrix, archive +
checksum packaging, the GitHub Release, and the installer /
Homebrew surfaces.

It does not replace Burrito, and anything beyond publishing
archives (signing, notarization, non-GitHub distribution, etc.) is
out of scope.

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

Or skip the manual edits entirely on a fresh `mix new` project:

```sh
mix tinfoil.init --install   # splices dep + config into mix.exs
mix tinfoil.init             # generates the workflow
```

That generates `.github/workflows/release.yml` and, if enabled, an
installer script, and a Homebrew formula template. Commit the
generated files and push a tag like `v0.1.0` to trigger the workflow.

> **Heads-up: your CLI needs an Application callback.** Burrito's
> `main_module` config key is **metadata only** — Burrito boots the
> BEAM but never calls `main/1` itself. Without an OTP application
> callback that reads argv and runs your CLI, the binary launches
> and just sits there until you SIGTERM it. The minimal pattern:
>
> ```elixir
> # mix.exs
> def application do
>   [extra_applications: [:logger], mod: {MyCli.Application, []}]
> end
>
> # lib/my_cli/application.ex
> defmodule MyCli.Application do
>   use Application
>
>   def start(_type, _args) do
>     if Burrito.Util.running_standalone?() do
>       spawn(fn ->
>         MyCli.run(Burrito.Util.Args.argv())
>         System.halt(0)
>       end)
>     end
>
>     Supervisor.start_link([], strategy: :one_for_one, name: MyCli.Supervisor)
>   end
> end
> ```
>
> The `running_standalone?/0` guard keeps `mix test` and `iex -S mix`
> from hijacking their own argv. See
> [`tinfoil_demo`](https://github.com/joshrotenberg/tinfoil_demo) for
> a full working example.

## Generated files

```
your-project/
├── .github/workflows/release.yml    ← CI pipeline (always)
├── .tinfoil/formula.rb.eex          ← if homebrew enabled
├── scripts/
│   ├── install.sh                   ← if installer enabled (Unix)
│   └── install.ps1                  ← if installer enabled (Windows)
└── mix.exs
```

The workflow runs a build job per configured target in parallel. Each
job calls `mix tinfoil.build`, which produces one `.tar.gz` with a
sha256 sidecar. A release job then collects the artifacts, calls
`mix tinfoil.publish` to create the GitHub Release, and (if homebrew
is enabled) calls `mix tinfoil.homebrew` to render the formula and
push it to the configured tap.

## Tasks

| Task                     | Description |
| ------------------------ | ----------- |
| `mix tinfoil.init`       | Print a suggested `:tinfoil` config snippet and, if one already exists, generate the workflow and supporting files. Pass `--install` to splice the tinfoil dep + a starter config into `mix.exs` and run `mix deps.get`. |
| `mix tinfoil.generate`   | Regenerate the workflow and scripts from the current config. Run after editing `:tinfoil` in mix.exs or upgrading tinfoil. |
| `mix tinfoil.plan`       | Print what would be built and released. Supports `--format human` (default), `--format json`, and `--format matrix` for GitHub Actions consumption. |
| `mix tinfoil.build`      | Build a single target: run `mix release` with the right `BURRITO_TARGET`, package the binary into a tar.gz, and write a sha256 sidecar. Called by the generated workflow once per matrix entry. |
| `mix tinfoil.publish`    | Create a GitHub Release from artifacts in `artifacts/` and upload every archive plus a combined `checksums-sha256.txt`. Tags containing `-rc`, `-beta`, or `-alpha` are marked as prereleases. Pass `--replace` to delete and recreate if a release for the tag already exists. |
| `mix tinfoil.homebrew`   | Render the Homebrew formula from `artifacts/` and push it to the configured tap. Honors `homebrew.auth` for choosing between a PAT (`HOMEBREW_TAP_TOKEN`) and an SSH deploy key. |

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

| Target             | Triple                          | GitHub runner       | Archive  |
| ------------------ | ------------------------------- | ------------------- | -------- |
| `:darwin_arm64`    | `aarch64-apple-darwin`          | `macos-latest`      | `.tar.gz`|
| `:darwin_x86_64`   | `x86_64-apple-darwin`           | `macos-15-intel`    | `.tar.gz`|
| `:linux_x86_64`    | `x86_64-unknown-linux-musl`     | `ubuntu-latest`     | `.tar.gz`|
| `:linux_arm64`     | `aarch64-unknown-linux-musl`    | `ubuntu-latest`     | `.tar.gz`|
| `:windows_x86_64`  | `x86_64-pc-windows-msvc`        | `ubuntu-latest`     | `.zip`   |

Triples follow the standard Rust-style convention since that is what
users expect to see in release asset names.

> **`:darwin_x86_64` uses `macos-15-intel`**, GitHub's last Intel
> runner label, available until August 2027. After that date, native
> x86_64 macOS runners will no longer exist on GitHub Actions. By then
> the Intel Mac install base will be small enough that dropping the
> target is likely the right call.

Windows and `linux_arm64` builds cross-compile from `ubuntu-latest`
via Zig; no native `windows-latest` or `ubuntu-24.04-arm` runner is
required. The cross-compiled `linux_arm64` default matters because
GitHub's ARM runner is only on paid plans -- free-tier users were
previously stuck on a queued job forever. Paid users who want a
native arm64 build can flip the runner back via `:extra_targets`.

Two installer scripts ship when `installer.enabled: true`:
`scripts/install.sh` for Unix (`curl | sh`) and `scripts/install.ps1`
for Windows (`iex (irm ...)`). Both resolve the latest release tag
from the GitHub API, download the right asset for the detected
OS/arch, verify against the combined `checksums-sha256.txt`, and
install to a sensible default directory (configurable via flags).

### Collapsing the build matrix

By default every target is its own CI job. Set
`single_runner_per_os: true` in your `:tinfoil` config to collapse
each OS family onto one job that builds every target in that family
sequentially:

```elixir
tinfoil: [
  targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64],
  single_runner_per_os: true
]
```

The runner used for each family is taken from the first target in
that family, so list the one you want to own the family first
(`:darwin_arm64` before `:darwin_x86_64` puts both on `macos-latest`
and cross-compiles the x86 slice via Zig). This trades wall-clock
parallelism for fewer runner-minutes; leave it off if your builds
don't contend for runners.

### Homebrew auth

The `homebrew:` job needs push access to the tap repo. Two auth
modes are supported:

**`auth: :token`** (default). The workflow expects a
`HOMEBREW_TAP_TOKEN` repo secret -- a Personal Access Token (classic
or fine-grained) with `contents: write` on the tap repo. The mix
task clones over HTTPS with the token baked into the URL.

**`auth: :deploy_key`**. Generate an SSH key pair, add the public
key to the tap repo's deploy keys (with write access), and set the
private key as the `HOMEBREW_TAP_DEPLOY_KEY` secret on the CLI
repo. The generated workflow installs
[`webfactory/ssh-agent`](https://github.com/webfactory/ssh-agent)
before running `mix tinfoil.homebrew`, which clones over SSH. Deploy
keys are scoped to a single repo and never expire, which is the main
reason to prefer them over PATs.

If your secret is named differently, override the name with
`homebrew: [token_secret: "YOUR_NAME"]` or
`homebrew: [deploy_key_secret: "YOUR_NAME"]`. The env var the mix
task reads is fixed; only the secret reference in the workflow is
configurable.

### Runtime output from the wrapped binary

A Burrito-wrapped binary prints a handful of diagnostic lines to
stderr on every invocation before your CLI output:

```
debug: Unpacked 977 files
debug: Going to clean up older versions of this application...
debug: Launching erlang...
[l] Uninstalled older version (v0.5.0)
```

These are emitted by Burrito's Zig wrapper (the `debug:` lines) and
its maintenance pass (the `[l]` line when an older cached version is
cleaned up). They are **not** tinfoil's output and tinfoil cannot
silence them from the outside -- the wrapper runs before any Elixir
code loads. Passing `debug: false` inside your `burrito:` config block
has no effect on these lines as of Burrito 1.5.

The noise is safe to redirect (`your_cli 2>/dev/null`) if it bothers
end users. Upstream tracking lives with Burrito; follow
<https://github.com/burrito-elixir/burrito> if a quieter mode lands.

### NIFs and cross-compilation

Burrito cross-compiles via Zig, which handles pure Erlang/Elixir deps
reliably but can struggle with NIFs (Rustler crates, `elixir_make` C
extensions, raw `c_src/` sources). `mix tinfoil.plan` inspects your
resolved deps and prints a warning for anything that looks like a NIF
so you know where to double-check your built artifacts. The warning
is informational -- many NIFs do cross-compile cleanly, and
`rustler_precompiled` sidesteps the issue when prebuilts cover your
targets.

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

  # Homebrew formula generation. Requires auth material for the tap
  # repo — either HOMEBREW_TAP_TOKEN (PAT) or an SSH deploy key.
  homebrew: [
    enabled: true,
    tap: "owner/homebrew-tap",
    formula_name: "my_cli", # defaults to the app name
    auth: :token            # or :deploy_key (default :token)
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
