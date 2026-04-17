# Mix tasks

Tinfoil ships six mix tasks. `mix tinfoil.init` and
`mix tinfoil.generate` are run by hand; the rest are called by the
generated workflow.

| Task                     | What it does |
| ------------------------ | ------------ |
| `mix tinfoil.init`       | Print a suggested `:tinfoil` config snippet and, if one already exists, generate the workflow and supporting files. Pass `--install` to splice the tinfoil dep + a starter config into `mix.exs` and run `mix deps.get`. |
| `mix tinfoil.generate`   | Regenerate the workflow and scripts from the current config. Run after editing `:tinfoil` in `mix.exs` or upgrading tinfoil. |
| `mix tinfoil.plan`       | Print what would be built and released. Supports `--format human` (default), `--format json`, and `--format matrix` for GitHub Actions consumption. |
| `mix tinfoil.build`      | Build a single target: run `mix release` with the right `BURRITO_TARGET`, package the binary into a `.tar.gz` (or `.zip` for Windows), and write a sha256 sidecar. Called by the generated workflow once per matrix entry. |
| `mix tinfoil.publish`    | Create a GitHub Release from artifacts in `artifacts/` and upload every archive plus a combined `checksums-sha256.txt`. Tags containing `-rc`, `-beta`, or `-alpha` are marked as prereleases. Pass `--replace` to delete and recreate if a release for the tag already exists. |
| `mix tinfoil.homebrew`   | Render the Homebrew formula from `artifacts/` and push it to the configured tap. Honors `homebrew.auth` for choosing between a PAT (`HOMEBREW_TAP_TOKEN`) and an SSH deploy key. |
| `mix tinfoil.scoop`      | Render the Scoop manifest from `artifacts/` and push it to the configured bucket. Honors `scoop.auth` for choosing between a PAT (`SCOOP_BUCKET_TOKEN`) and an SSH deploy key. Requires `:windows_x86_64` in `:targets`. |

The generated workflow invokes `mix tinfoil.build` and
`mix tinfoil.publish` directly, so tinfoil version bumps usually
take effect the next time the workflow runs without needing to
regenerate the YAML.

## When to regenerate

Run `mix tinfoil.generate` after:

- editing the `:tinfoil` keyword in `mix.exs`,
- upgrading tinfoil to a version that changes the workflow
  template (release notes will call this out), or
- switching Homebrew or Scoop auth mode between `:token` and
  `:deploy_key`.

You do not need to regenerate for most tinfoil point releases; the
workflow delegates to `mix tinfoil.build` / `mix tinfoil.publish`,
so logic changes land automatically.

## Preview before you tag

```sh
mix tinfoil.plan
```

Prints the resolved target map, the archive names that would be
produced, and the distribution surfaces that are enabled. Useful
as a sanity check after editing config.
