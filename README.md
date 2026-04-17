# tinfoil

[![CI](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/tinfoil/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinfoil.svg)](https://hex.pm/packages/tinfoil)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tinfoil)
[![License](https://img.shields.io/hexpm/l/tinfoil.svg)](https://github.com/joshrotenberg/tinfoil/blob/main/LICENSE)

Release automation for [Burrito](https://github.com/burrito-elixir/burrito)-based Elixir CLIs. Tag a version, tinfoil ships the binaries.

## What you get

A pushed `v*` tag produces:

- Cross-compiled binaries for darwin (arm64, x86_64), linux (arm64,
  x86_64 musl), and windows (x86_64), built on GitHub Actions and
  cross-compiled via Zig (no native ARM or Windows runner needed).
- A GitHub Release with every archive attached, a combined
  `checksums-sha256.txt`, and build-provenance attestations.
- An optional `curl | sh` installer (Unix) and `iex (irm ...)`
  installer (Windows).
- An optional Homebrew formula pushed to your tap
  (macOS + Linux via Linuxbrew).
- An optional Scoop manifest pushed to your bucket (Windows).
- A regeneratable workflow -- `mix tinfoil.generate` rewrites
  `.github/workflows/release.yml` from your `mix.exs` config, so
  upgrading tinfoil upgrades the pipeline.

All configured via one `:tinfoil` keyword in `mix.exs`; no
hand-edited YAML. See
[`tinfoil_demo`](https://github.com/joshrotenberg/tinfoil_demo) for
a full working project.

> **Status:** pre-1.0. The mix tasks, workflow template, and Hex
> publish loop are all in place and dogfooded against a real Burrito
> project. Defaults and target strategies are still evolving -- pin
> to an exact minor version if you need stability.

## Quick start

On a fresh `mix new` project:

```sh
mix tinfoil.init --install   # splices dep + starter config into mix.exs
mix tinfoil.init             # generates .github/workflows/release.yml
git add . && git commit -m "feat: add tinfoil"
git tag v0.1.0 && git push --follow-tags
```

That is the whole flow. Every subsequent tagged push produces a
full release.

To also automate the version-bumping side with release-please (so
tagging becomes "merge the release PR"), see the
[release-please guide](https://hexdocs.pm/tinfoil/release_please.html).

## Documentation

Full docs live on [hexdocs.pm/tinfoil](https://hexdocs.pm/tinfoil):

| Guide | What's in it |
|-------|--------------|
| [Getting started](https://hexdocs.pm/tinfoil/getting_started.html) | Install, configure, first release, Application callback pattern. |
| [Configuration](https://hexdocs.pm/tinfoil/configuration.html) | Every option in the `:tinfoil` keyword. |
| [Targets and runners](https://hexdocs.pm/tinfoil/targets.html) | Target matrix, Burrito target resolution, cross-compilation, NIFs. |
| [Distribution](https://hexdocs.pm/tinfoil/distribution.html) | Homebrew, Scoop, installers, prerelease handling, attestations. |
| [Automatic releases with release-please](https://hexdocs.pm/tinfoil/release_please.html) | Wiring release-please to tinfoil; the `GITHUB_TOKEN` gotcha and three fixes. |
| [Mix tasks](https://hexdocs.pm/tinfoil/mix_tasks.html) | Task reference. |

## Related projects

- [Burrito](https://github.com/burrito-elixir/burrito) -- builds
  self-contained Elixir binaries. Required peer dependency.
- [cargo-dist](https://opensource.axo.dev/cargo-dist/) -- the
  equivalent tool in the Rust/Cargo ecosystem. Tinfoil borrows the
  pattern of a generated CI workflow that calls back into the tool
  via mix tasks, so upgrading the tool upgrades the pipeline.

## License

MIT.
