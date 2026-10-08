# Releasing

Aixle Flow is released as `vX.Y.Z` tags on `develop`, following
[Semantic Versioning](https://semver.org/) from **1.0.0**. A tag is the only thing that
publishes images; a merge to `develop` publishes nothing.

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
