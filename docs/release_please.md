# Automatic releases with release-please

Tinfoil's generated `release.yml` reacts to a pushed git tag by
default. It can instead react to a published GitHub Release, or be
invoked directly as a reusable workflow, via `:trigger`. To automate
the "bump the version + update changelog + cut the tag" side of that
loop,
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

This affects **both** event-based triggers, not just the default:

| trigger | event release-please creates | fires? |
|---|---|---|
| `:tag_push` | the `v*` tag | no |
| `:release_published` | the GitHub Release | no |

Release-please creates both with `GITHUB_TOKEN` unless you explicitly
hand it a PAT, so with a stock setup the tag and release appear, no
`release.yml` run ever starts, and the release simply has no binaries.
Nothing errors. This is the single most common way to end up with a
release and no attached artifacts.

Option 4 below sidesteps the rule entirely and is the recommended
choice for a stock release-please repo. Options 1-3 make the events
attributable to a user instead.

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

Caveat: `release.yml` runs on the *workflow_dispatch* event, not the
tag push, so the generated workflow has to accept that trigger. The
default `:tag_push` template only accepts `on: push: tags`, so this
option needs `trigger: :workflow_call`, which emits a
`workflow_dispatch` with a `tag` input alongside the callable entry
point.

At which point Option 4 is strictly simpler: if you are already
setting that trigger, calling the workflow with `uses:` is one less
moving part than dispatching it and waiting for a separate run.

### Option 4: Call the workflow directly (recommended)

Instead of hoping an event propagates, have the release-please
workflow invoke tinfoil's workflow as a reusable one, in the same run.
No event is involved, so the `GITHUB_TOKEN` rule never applies and no
long-lived credential is needed.

```elixir
tinfoil: [
  targets: [:darwin_arm64, :linux_x86_64],
  trigger: :workflow_call
]
```

`mix tinfoil.generate` then emits:

```yaml
on:
  workflow_call:
    inputs:
      tag:
        description: "Tag to build and attach assets to. Defaults to the calling workflow's release event tag."
        required: false
        type: string
  workflow_dispatch:
    inputs:
      tag:
        description: "Tag to build and attach assets to, e.g. v1.2.3"
        required: true
        type: string
```

Add a job to `release-please.yml` that calls it:

```yaml
  binaries:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created == 'true' }}
    uses: ./.github/workflows/release.yml
    with:
      tag: ${{ needs.release-please.outputs.tag_name }}
    secrets: inherit
```

The binaries job then sits alongside your other post-release jobs
(Hex publish, container build, deploy) instead of living at the far
end of an event that may never arrive.

Two details the generated workflow handles for you, both consequences
of a `workflow_call` run inheriting the *caller's* ref:

- `GITHUB_REF_NAME` is the caller's branch, usually `main`, not the
  tag. So `tinfoil.build`, `tinfoil.publish`, `tinfoil.homebrew`, and
  `tinfoil.scoop` are all invoked with an explicit `--tag`. For the
  build that is the difference between checking mix.exs against
  `v1.2.3` and against `main`.
- `actions/checkout` would otherwise take that same branch and build
  whatever is on it now, which is not necessarily the commit the tag
  points at. Every checkout pins `ref:` to the tag.

`workflow_dispatch` is emitted alongside so a failed release can be
re-run from the Actions tab by typing the tag, without retagging.
The tag-push trigger cannot offer that.

Publishing still runs in `--attach` mode, since release-please created
the release earlier in the same run. See the next section.

## Preserving the release-please changelog: attach mode

Release-please does not only create the tag. It creates the GitHub
Release too, and writes the curated changelog section as the body.

With the default `trigger: :tag_push`, tinfoil's workflow fires on
the tag and tries to create that same release. It already exists, so
publish fails with `release_already_exists_no_replace`. Reaching for
`--replace` does work, but it deletes the release and recreates it
from commit-derived notes, discarding the changelog release-please
just wrote.

Any trigger other than `:tag_push` switches the publish step to
`mix tinfoil.publish --attach`, which looks the release up by tag and
uploads only the assets. The body, prerelease flag, and draft state
stay exactly as release-please wrote them.

Both non-default triggers give you that:

```elixir
trigger: :workflow_call       # Option 4, recommended
trigger: :release_published   # needs Option 1, 2, or 3 for the token rule
```

Ordering is why attach pairs with the trigger rather than being a
standalone flag. On `push: tags` the workflow races release-please:
the tag lands first, so `--attach` would intermittently find no
release and fail. Both other triggers run only once the release object
exists, so the lookup always succeeds.

Two things to know:

- `:release_published` is still subject to the token rule above. It is
  a workflow-triggering event like any other, so a release created by
  a job authenticated as `GITHUB_TOKEN` will not start a run. Pair it
  with Option 1, 2, or 3, or use `:workflow_call`, which has no such
  constraint.
- `github: [draft: true]` has no effect in attach mode. Attach never
  edits the release, so draft state belongs to whatever created it.
  The generated workflow omits `--draft` accordingly.

If release-please is configured to create a *draft* release, the
`published` event does not fire until you publish it by hand. That is
a deliberate human gate, not a failure, but it does mean the binaries
appear a moment after the release does. `:workflow_call` is not
affected, since it does not wait on an event at all.

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
