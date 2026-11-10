# Releasing

Aixle Flow is released as `vX.Y.Z` tags on `develop`, following
[Semantic Versioning](https://semver.org/) from **1.0.0**. A tag is the only thing that
publishes images; a merge to `develop` publishes nothing. The runner, `aixle-runner`, is
released on its own `runner-vX.Y.Z` tags ([Releasing the runner](#releasing-the-runner)).

## What a version number promises

The contract is what a self-hosted deployment depends on: configuration, the database,
the HTTP and MCP APIs, and the runtimes it can launch.

| Bump | When |
| --- | --- |
| **Major** (`2.0.0`) | An upgrade needs an operator's hand: a configuration variable renamed or removed without a fallback, a migration that cannot run unattended, a breaking change to the REST or MCP API, a runtime removed. The changelog entry says what to do. |
| **Minor** (`1.1.0`) | New features, new runtimes, new configuration with a working default, deprecations. |
| **Patch** (`1.0.1`) | Fixes, and raised CLI pins in `config/agent_runtimes.json` — a vendor's CLI update ships as a patch release. |

Pre-releases (`v1.1.0-rc.1`) exist for trying a release on staging first. They publish
their own image tags only, never `latest`, and get no changelog section: their GitHub
Release (marked pre-release) shows `[Unreleased]` as of the tagged commit. Tag them
straight from `develop`, without a changelog PR.

## What a release publishes

Pushing `vX.Y.Z` runs two workflows:

- **`images.yml`** publishes every image — `flow-web`, `flow-otlp-ingest`,
  `flow-agent-base-core` and one `flow-<image>` per entry in `config/agent_runtimes.json`
  — to `ghcr.io/aixlehq` as `X.Y.Z`, plus `X.Y`, `X` and `latest` for a stable release.
  The web image carries `APP_VERSION=X.Y.Z` (the Sentry release) and
  `AGENT_IMAGE_TAG=X.Y.Z`, so it launches the agent images built with it. A deployment
  that pins `flow-web:X.Y.Z` therefore runs one version end to end.
- **`release.yml`** checks that the tag is on `develop` and creates the GitHub Release,
  whose notes are the `[X.Y.Z]` section of `CHANGELOG.md`, the image list, and the PRs
  merged since the previous tag.

## Cutting a release

1. **Changelog PR.** On a branch off `develop`, run
   `docker compose exec -T web bin/changelog release X.Y.Z`. It moves everything under
   `[Unreleased]` into a dated `[X.Y.Z]` section and updates the compare links. Read the
   section as a user would — it is the release announcement — then open the PR as
   `chore(release): X.Y.Z`.
2. **Merge it**, after CI is green.
3. **Tag the merge commit** and push the tag:

   ```bash
   git fetch origin develop
   git tag -a vX.Y.Z -m "vX.Y.Z" origin/develop
   git push origin vX.Y.Z
   ```

   The tag has to be pushed by a person: a tag created with a workflow's `GITHUB_TOKEN`
   starts no other workflow, so nothing would be published.
4. **Check both runs** (`Build Images`, `Release`) and the GitHub Release.

`bin/changelog notes X.Y.Z` prints a section exactly as the release will show it.

## Runner compatibility

`aixle-runner`, the program a customer runs on their own machine, has versions of its own,
independent of the application's (docs/design/agent-runtimes/DESIGN.md §14.2). What the platform
accepts is pinned in committed configuration, the `runners.release` block of
`config/settings.yml`:

- **Platform `X.Y` supports runner protocol versions `[N-1, N]` and runners at or above
  `min_version`, as the `runners.release` block of `config/settings.yml` declares at that
  release.** Its
  `protocol_supported` lists the protocol versions (`[1]` until the first protocol bump, the
  current and the previous one after it), and a runner below `min_version` is refused when it
  registers, with a message that names the minimum. A session is never stopped because a newer
  runner came out.
- **`recommended_version`** is what an idle machine below it is offered: it updates itself to
  that version, unless its runner or the machine opted out (`config.auto_update: false`, or
  `aixle-runner configure --no-auto-update`).
- **`binaries`** pins the SHA-256 of every runner binary the platform serves. The platform
  serves nothing else: `GET /runner/v1/releases/:version/:os-:arch` redirects only to a pinned
  binary, with its pinned digest.

Changing any of these is an application PR to the `runners.release` block of
`config/settings.yml`, and the changelog entry of that PR says what changed, so the release notes
state each release's runner compatibility. An invalid block fails the application's boot.

## Releasing the runner

A runner release is a `runner-vX.Y.Z` tag on `develop`, and nothing else publishes one: an
application `vX.Y.Z` tag never builds a runner, and a `runner-v*` tag runs neither `images.yml`
nor `release.yml`.

1. **Dry run.** Run `Runner Release` (`.github/workflows/runner-release.yml`) by hand from the
   Actions tab with a version such as `0.2.0-dryrun.1`. It runs the Go checks, builds both
   binaries, writes `checksums.txt`, checks that the binaries are static and report that
   version, and builds the image for both platforms, and it pushes and releases nothing.
2. **Tag** the commit on `develop`, as a person, for the same reason as above:

   ```bash
   git fetch origin develop
   git tag -a runner-vX.Y.Z -m "runner-vX.Y.Z" origin/develop
   git push origin runner-vX.Y.Z
   ```

   The run attaches `aixle-runner-linux-amd64`, `aixle-runner-linux-arm64` and `checksums.txt`
   to a GitHub Release, which is never marked the repository's latest, and pushes
   `ghcr.io/aixlehq/aixle-runner:X.Y.Z`. A pre-release (`runner-vX.Y.Z-rc.1`) is marked as one.
   The image does not update itself: it sets `AIXLE_RUNNER_NO_SELF_UPDATE=1`, because in a
   container the image tag is the version (DESIGN.md §14.4).
3. **Pin it.** Publishing changes nothing on the platform yet. An application PR adds the
   version and the SHA-256 of `linux-amd64` and `linux-arm64` under `binaries` in the
   `runners.release` block of `config/settings.yml`, taken from the release's `checksums.txt`
   (`gh release download runner-vX.Y.Z -R AixleHQ/flow -p checksums.txt`), and moves
   `recommended_version` (and, when older runners must go, `min_version`) with a changelog entry.
   Machines start updating once that PR is deployed.

## Writing the changelog

Every PR with a user-visible change adds its entry under `[Unreleased]` in the same PR —
prefixed with its product area from
[product/changelog-product-areas.md](../product/changelog-product-areas.md) — so cutting
a release is a move, not an archaeology session. PR titles are Conventional Commits
(checked by `pr-title.yml`), because the squash-merged title is the line the release
notes list for that PR.

## Rolling back

Deploy the previous version's images. Two things decide whether that is safe:

- **Migrations do not roll back.** A release that ran a migration the previous code
  cannot read (a dropped or renamed column) cannot be rolled back past; write such
  changes expand/contract, so the release that adds a column is not the one that drops
  the old one.
- **Temporal histories.** Workflows started on the newer release replay on the older
  code. A workflow change guarded with `patched` replays safely in both directions;
  see [architecture/temporal-versioning.md](../architecture/temporal-versioning.md).
