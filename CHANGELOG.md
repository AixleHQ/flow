# Changelog

All notable changes to Aixle Flow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/) once
tagged releases begin. Entries a *user* sees in the product carry a product
area from
[docs/product/changelog-product-areas.md](docs/product/changelog-product-areas.md)
as their prefix; repository-level entries a *contributor* needs — licensing,
governance, community health — carry none.

> Versioning and tagged releases begin with the open-source launch. The first
> tag will be **`v0.1.0`** (the project is pre-1.0), cut from the *Unreleased*
> changes below — likely accompanied by prebuilt images. Until that launch,
> notable changes accumulate here under *Unreleased*.

## [Unreleased]

### Added
- **Workflows**: version history. The builder keeps edits local until **Save**
  (with an *Unsaved changes* notice and a prompt before leaving), and each Save
  records the whole workflow as one numbered version. The History view shows
  who changed what — a person, or the Aixle Builder on their behalf — with a
  diff against the previous or the current version, and reverts to any version
  by saving it as the newest. A Save over someone else's newer version is
  refused instead of overwriting it.
- **Agents**, **Skills**, **Wrappers**, **Connectors**: the same version
  history, diff and revert. Connector secrets never enter a version.
- **Sessions & Runs**: the run page names the workflow version each session
  launched with, and says when the workflow was saved mid-run.
- Apache License 2.0, `NOTICE` attribution file, and third-party license
  inventory (`THIRD-PARTY-LICENSES.md`, `NOTICES.md`).
- Contributor model: Contributor License Agreement (`CLA.md`) and Developer
  Certificate of Origin (`DCO`) sign-off, documented in `CONTRIBUTING.md`.
- **Docs**: public documentation portal at `/docs`.
- Open-source documentation layer: README, ROADMAP, quickstart, user guide, and
  reference content.
- Community health files: Code of Conduct, Security Policy, Governance, issue
  and pull-request templates, CODEOWNERS, and this changelog.

### Changed
- **Workflows**, **Agents**, **Skills**, **Wrappers**, **Connectors**: delete
  is now archive. Archived entities keep their history, leave pickers and new
  sessions, and can be restored from each screen's *Archived* view; archiving
  is refused while a workflow uses the entity. Workflow steps and sub-steps
  are always soft-deleted.
- Configuration: every deployment input is now declared in `config/settings.yml`
  and documented in `docs/reference/configuration.md`, which the docs portal
  serves directly instead of a hand-copy. A test fails when a variable gains no
  row, or a row names a variable nothing reads.
- The Active Record pool now falls back to the same `RAILS_MAX_THREADS` default
  Puma does (10). A deployment that never set the variable previously ran 10
  request threads against an 8-connection pool.
- Agent runtime images are derived from `AGENT_IMAGE_PREFIX` +
  `AGENT_IMAGE_TAG`, with the seven per-runtime `AGENT_IMAGE_*` variables kept
  as overrides. Resolved images are unchanged in every environment.

### Removed
- Configuration nothing read: `AUTHOR_NAME`, `AUTHOR_EMAIL`, `RAILS_PORT`,
  `TEMPORAL_UI_URL`, `REDIS_UI_URL`, `TRAEFIK_DASHBOARD_URL`,
  `TRAEFIK_CORS_ORIGINS`, `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`, `CODER_DEFAULT_TEMPLATE`,
  `CODER_MACHINE_PREFIX`, `MAX_FILE_SIZE`, `ENVIRONMENT`. Setting them now has
  no effect; they can be dropped from ConfigMaps, compose files and CI build
  args.

[Unreleased]: https://github.com/AixleHQ/flow/commits/develop
