# Targets and runners

Tinfoil uses abstract target atoms (`:darwin_arm64`,
`:linux_x86_64`, and so on) independent of whatever names you choose
in your Burrito config. At load time, tinfoil reads your
`releases/0` block and matches each tinfoil target to a Burrito
target by `[os:, cpu:]` pair.

## Supported targets

| Target             | Triple                          | GitHub runner       | Archive  |
| ------------------ | ------------------------------- | ------------------- | -------- |
| `:darwin_arm64`    | `aarch64-apple-darwin`          | `macos-latest`      | `.tar.gz`|
| `:darwin_x86_64`   | `x86_64-apple-darwin`           | `macos-15-intel`    | `.tar.gz`|
| `:linux_x86_64`    | `x86_64-unknown-linux-musl`     | `ubuntu-latest`     | `.tar.gz`|
| `:linux_arm64`     | `aarch64-unknown-linux-musl`    | `ubuntu-latest`     | `.tar.gz`|
| `:windows_x86_64`  | `x86_64-pc-windows-msvc`        | `ubuntu-latest`     | `.zip`   |

Triples follow the standard Rust-style convention since that is
what users expect to see in release asset names.

Windows and `linux_arm64` builds cross-compile from `ubuntu-latest`
via Zig; no native `windows-latest` or `ubuntu-24.04-arm` runner is
required. The cross-compiled `linux_arm64` default matters because
GitHub's ARM runner is only on paid plans -- free-tier users were
previously stuck on a queued job forever. Paid users who want a
native arm64 build can flip the runner back via `:extra_targets`.

> **`:darwin_x86_64` uses `macos-15-intel`**, GitHub's last Intel
> runner label, available until August 2027. After that date, native
> x86_64 macOS runners will no longer exist on GitHub Actions. By
> then the Intel Mac install base will be small enough that dropping
> the target is likely the right call.

## How resolution works

Suppose your app declares custom Burrito target names:

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
`my_cli-0.1.0-aarch64-apple-darwin.tar.gz`. If a tinfoil target has
no matching Burrito target, `Tinfoil.Config.load/1` returns an
error at plan time naming the expected `[os:, cpu:]` pair.

## BURRITO_TARGET is not readable from mix.exs

Tinfoil sets `BURRITO_TARGET` and then runs the release task in the
same process. `mix.exs` is evaluated at Mix startup, before any task
runs, so `System.get_env("BURRITO_TARGET")` is always `nil` while
`releases/0` is being built.

This matters if you share one release entry between Burrito binaries
and something else, which is the normal shape for a project that also
ships a container image. The Dockerfile runs plain `mix release` and
wants an assembled release; `mix tinfoil.build` wants a wrapped
binary. The tempting gate does not work:

```elixir
# Does NOT work: the env var is always nil here.
steps: if(System.get_env("BURRITO_TARGET"),
         do: [:assemble, &Burrito.wrap/1],
         else: [:assemble])
```

It silently takes the `else` branch, `mix release` assembles normally,
and the build fails at the next step complaining about a missing
`burrito_out/` binary.

Gate on the invoked task instead. `System.argv/0` *is* populated when
`mix.exs` is evaluated:

```elixir
defp burrito_build? do
  System.get_env("BURRITO_TARGET") != nil or
    match?(["tinfoil.build" | _], System.argv())
end

# in releases/0
steps: if(burrito_build?(), do: [:assemble, &Burrito.wrap/1], else: [:assemble])
```

The env-var check is kept first so the gate still works if you invoke
`mix release` yourself with `BURRITO_TARGET` exported.

A consequence of the shared process: every target in a
`single_runner_per_os` job shares one BEAM and one cached
`Mix.Project` config, so per-target project configuration cannot vary
within a job.

## Previewing the plan

`mix tinfoil.plan` prints the resolved target map read-only:

```
$ mix tinfoil.plan
tinfoil plan for my_cli 0.1.0

  target         burrito   runner         archive
  -------------  --------  -------------  -----------------------------------------------
  darwin_arm64   macos_m1  macos-latest   my_cli-0.1.0-aarch64-apple-darwin.tar.gz
  linux_x86_64   linux     ubuntu-latest  my_cli-0.1.0-x86_64-unknown-linux-musl.tar.gz

  format:    tar_gz (sha256)
  github:    owner/my_cli (draft: false)
  homebrew:  disabled
  installer: ~/.local/bin
```

For CI consumption, `--format matrix` emits a compact GitHub
Actions matrix fragment:

```yaml
- id: plan
  run: echo "matrix=$(mix tinfoil.plan --format matrix)" >> "$GITHUB_OUTPUT"

build:
  needs: plan
  strategy:
    matrix: ${{ fromJson(needs.plan.outputs.matrix) }}
```

## Collapsing the matrix

By default every target is its own CI job. Set
`single_runner_per_os: true` to collapse each OS family onto one
job that builds every target in that family sequentially:

```elixir
tinfoil: [
  targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64],
  single_runner_per_os: true
]
```

The runner used for each family is taken from the first target in
that family, so list the one you want to own the family first.
`:darwin_arm64` before `:darwin_x86_64` puts both on `macos-latest`
and cross-compiles the x86 slice via Zig.

This trades wall-clock parallelism for fewer runner-minutes; leave
it off if your builds don't contend for runners.

## NIFs and cross-compilation

Burrito cross-compiles via Zig, which handles pure Erlang/Elixir
deps reliably but can struggle with NIFs (Rustler crates,
`elixir_make` C extensions, raw `c_src/` sources).
`mix tinfoil.plan` inspects your resolved deps and prints a warning
for anything that looks like a NIF so you know where to double-check
your built artifacts.

The warning is informational. Many NIFs do cross-compile cleanly,
and `rustler_precompiled` sidesteps the issue when prebuilts cover
your targets.

## Runtime output from the wrapped binary

A Burrito-wrapped binary prints a handful of diagnostic lines to
stderr on every invocation before your CLI output:

```
debug: Unpacked 977 files
debug: Going to clean up older versions of this application...
debug: Launching erlang...
[l] Uninstalled older version (v0.5.0)
```

These are emitted by Burrito's Zig wrapper (the `debug:` lines) and
its maintenance pass (the `[l]` line when an older cached version
is cleaned up). They are **not** tinfoil's output and tinfoil
cannot silence them from the outside -- the wrapper runs before any
Elixir code loads. Passing `debug: false` inside your `burrito:`
config block has no effect on these lines as of Burrito 1.6.

The noise is safe to redirect (`your_cli 2>/dev/null`) if it
bothers end users. Upstream tracking lives with Burrito; follow
<https://github.com/burrito-elixir/burrito> if a quieter mode lands.
