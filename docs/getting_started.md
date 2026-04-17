# Getting started

Tinfoil generates a GitHub Actions workflow that cross-compiles a
Burrito-based Elixir CLI and ships it as a GitHub Release on every
tag. This guide covers the minimum you need to get to a working
release.

For a full worked example, see the
[`tinfoil_demo`](https://github.com/joshrotenberg/tinfoil_demo)
repo.

## Add the dependency

Add `:tinfoil` alongside `:burrito` in `mix.exs`:

```elixir
def deps do
  [
    {:burrito, "~> 1.0"},
    {:tinfoil, "~> 0.2", runtime: false}
  ]
end
```

> **Don't set `only: :dev`.** The generated CI workflow runs
> `MIX_ENV=prod mix tinfoil.build`, so tinfoil must compile in the
> prod environment too. `runtime: false` keeps it out of the started
> applications at runtime while still making the mix tasks available
> during builds.

## Configure

Add a `:tinfoil` key to `project/0`:

```elixir
def project do
  [
    app: :my_cli,
    version: "0.1.0",
    # ...
    tinfoil: [
      targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64],
      homebrew: [enabled: true, tap: "owner/homebrew-tap"],
      installer: [enabled: true]
    ]
  ]
end
```

The only required key is `:targets`. Every other knob has a sensible
default, covered in the
[configuration reference](configuration.md).

You also need a Burrito `:releases` block. Tinfoil resolves its
abstract target atoms against your Burrito target names by matching
`[os:, cpu:]` pairs, so the names inside your `:releases` block can
be anything; see [targets and runners](targets.md) for how resolution
works.

## Your CLI needs an Application callback

Burrito's `main_module` config key is metadata only. Burrito boots
the BEAM but never calls `main/1` itself. Without an OTP application
callback that reads argv and runs your CLI, the binary launches and
hangs until you SIGTERM it. The minimal pattern:

```elixir
# mix.exs
def application do
  [extra_applications: [:logger], mod: {MyCli.Application, []}]
end

# lib/my_cli/application.ex
defmodule MyCli.Application do
  use Application

  def start(_type, _args) do
    if Burrito.Util.running_standalone?() do
      spawn(fn ->
        MyCli.run(Burrito.Util.Args.argv())
        System.halt(0)
      end)
    end

    Supervisor.start_link([], strategy: :one_for_one, name: MyCli.Supervisor)
  end
end
```

The `running_standalone?/0` guard keeps `mix test` and `iex -S mix`
from hijacking their own argv.

## Generate the workflow

```sh
mix deps.get
mix tinfoil.init
```

On a fresh `mix new` project, you can skip the manual edits entirely:

```sh
mix tinfoil.init --install   # splices dep + starter config into mix.exs
mix tinfoil.init             # generates the workflow + supporting files
```

Generated layout:

```
your-project/
├── .github/workflows/release.yml    ← CI pipeline (always)
├── .tinfoil/formula.rb.eex          ← if homebrew enabled
├── scripts/
│   ├── install.sh                   ← if installer enabled (Unix)
│   └── install.ps1                  ← if installer enabled (Windows)
└── mix.exs
```

Commit the generated files.

## Ship a release

```sh
git tag v0.1.0
git push --tags
```

The push fires `.github/workflows/release.yml`, which builds every
target in parallel, packages each binary with its sha256, and
publishes a GitHub Release with every archive attached. If you
enabled Homebrew or Scoop, the tap and bucket repos are updated in
the same run.

## Automating version bumps

Tinfoil's generated workflow only reacts to tag pushes. A typical
next step is adding
[release-please](https://github.com/googleapis/release-please) to
open rolling release PRs driven by conventional commits, so tagging
becomes "merge the release PR."

The wiring has a couple of GitHub-specific auth gotchas, documented
in [Automatic releases with release-please](release_please.md).

## Next

- [Configuration reference](configuration.md) -- every option in the
  `:tinfoil` keyword.
- [Targets and runners](targets.md) -- how abstract targets map to
  Burrito targets and GitHub runners.
- [Distribution](distribution.md) -- Homebrew, Scoop, installers,
  prerelease handling.
- [Mix tasks](mix_tasks.md) -- task-level reference.
