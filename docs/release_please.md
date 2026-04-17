# Automatic releases with release-please

Tinfoil's generated `release.yml` reacts to a pushed git tag. To
automate the "bump the version + update changelog + cut the tag"
side of that loop,
[release-please](https://github.com/googleapis/release-please) is
the standard GitHub-native choice. This guide shows how to wire it
up for a tinfoil'ed Burrito app and documents the one critical
gotcha most people hit.

## What release-please does

Release-please watches `main` for conventional-commit messages
(`feat:`, `fix:`, etc.), maintains a rolling "release PR" that
accumulates changelog entries and a proposed version bump, and
when you merge that PR, creates the git tag plus a GitHub Release
object.

You still get one human gate (merging the PR). Everything else is
automatic.

## The gotcha: `GITHUB_TOKEN` suppresses downstream workflows

GitHub's Actions runtime has an anti-recursion rule: resources
(tags, releases, pushes) created by a workflow that authenticated
as `GITHUB_TOKEN` will not trigger new workflow runs.

That is a problem here because tinfoil's `release.yml` fires on:

```yaml
on:
  push:
    tags: ["v*"]
```

If release-please creates the tag using `GITHUB_TOKEN`, the tag
shows up in the repo but no `release.yml` run starts. No binaries
ship. Silent failure.

There are three workarounds. Pick one.

### Option 1: Personal Access Token (simplest)

Create a classic PAT with `repo` scope (or a fine-grained PAT with
`contents: write`, `pull-requests: write`, and `issues: write` on
the repo). Add it to the repo as a secret named `COMMITTER_TOKEN`,
then point release-please at it:

```yaml
# .github/workflows/release-please.yml
name: Release Please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.COMMITTER_TOKEN }}
```

The tag is now created by your PAT's identity, which counts as a
distinct actor from `GITHUB_TOKEN`. `release.yml` fires normally.

This is the path `tinfoil_demo` uses.

Downsides: PATs expire (classic: manual renewal; fine-grained: up
to a year), and they belong to a human account, so offboarding
that human breaks releases.

### Option 2: GitHub App (cleanest long-term)

Create a GitHub App with the same permissions, install it on the
repo, and generate an installation token at workflow runtime:

```yaml
jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/create-github-app-token@v1
        id: app-token
        with:
          app-id: ${{ vars.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ steps.app-token.outputs.token }}
```

Tags are now authored as `<your-app>[bot]`. Same "distinct actor"
effect; downstream workflows fire. No per-human expiry; install
the App on as many repos as you want.

Higher setup cost; requires App creation + install. Worth it once
you have more than one repo using this pattern.

### Option 3: Explicit workflow dispatch (no extra auth)

Leave release-please on `GITHUB_TOKEN` and have the release-please
job explicitly dispatch `release.yml` after creating the release:

```yaml
      - name: Trigger tinfoil release
        if: ${{ steps.release.outputs.release_created }}
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ steps.release.outputs.tag_name }}
        run: gh workflow run release.yml --ref "$TAG"
```

This is what tinfoil itself uses internally for its dogfood smoke
test.

Caveat: `release.yml` runs on the *workflow_dispatch* event, not
the tag push, so the generated workflow needs to accept both
triggers. The default tinfoil template only accepts
`on: push: tags`; you would need to hand-edit
`.github/workflows/release.yml` after `mix tinfoil.generate` to
also accept `workflow_dispatch` with a `tag` input. In practice,
Option 1 or 2 is less fragile.

## Full example

A minimal `release-please.yml` for an Elixir/Burrito CLI using a
PAT (Option 1):

```yaml
name: Release Please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.COMMITTER_TOKEN }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

`release-please-config.json`:

```json
{
  "packages": {
    ".": {
      "release-type": "elixir",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": true
    }
  },
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
}
```

`.release-please-manifest.json` (initial contents; release-please
updates it on each release):

```json
{ ".": "0.1.0" }
```

The `elixir` release-type teaches release-please where to bump the
version inside `mix.exs`.

`bump-patch-for-minor-pre-major: true` keeps `feat:` commits on a
patch bump while you are still in the `0.x` range, matching
typical pre-1.0 hex convention.

## Secrets checklist

For a fully automated flow on a tinfoil'ed Burrito app, you need
these repo secrets configured:

| Secret                      | Used by                   | Required? |
| --------------------------- | ------------------------- | --------- |
| `COMMITTER_TOKEN` (or App)  | release-please-action     | Yes (pick one auth option) |
| `HEX_API_KEY`               | `mix hex.publish`         | If publishing a hex package |
| `HOMEBREW_TAP_TOKEN` or `HOMEBREW_TAP_DEPLOY_KEY` | `mix tinfoil.homebrew` | If `homebrew.enabled` |
| `SCOOP_BUCKET_TOKEN` or `SCOOP_BUCKET_DEPLOY_KEY` | `mix tinfoil.scoop`    | If `scoop.enabled` |

Most projects with all four surfaces enabled end up reusing one
`COMMITTER_TOKEN` across release-please, Homebrew, and Scoop by
setting `token_secret: "COMMITTER_TOKEN"` in both the `:homebrew`
and `:scoop` blocks. That collapses the number of PATs to manage
from three to one.

## End-to-end flow with release-please

1. Commit with conventional-commit messages (`feat:`, `fix:`)
   and push to `main`.
2. `release-please.yml` runs and opens (or updates) a release PR
   titled "chore(main): release X.Y.Z".
3. Merge the release PR.
4. release-please creates the `vX.Y.Z` tag and a GitHub Release
   stub.
5. The tag push fires `release.yml` (generated by tinfoil).
6. Tinfoil builds every target, uploads archives + attestations,
   and populates the GitHub Release with binaries + checksums.
7. If enabled, Homebrew formula and Scoop manifest are pushed to
   their tap/bucket repos.

Step 5 is the one that only works if release-please is
authenticated as something other than `GITHUB_TOKEN`.
