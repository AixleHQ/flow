# Documentation Index

**Project:** Aixle

All architecture, design, research, and strategy docs live under `docs/`. Whenever
a document is added, removed, or moved here, update this index in the same change
(see CLAUDE.md).

---

## Project

- **[project/overview.md](./project/overview.md)** — Executive summary, tech stack, architecture overview, data model, API structure
- **[project/context.md](./project/context.md)** — LLM-optimized rules: tech stack, patterns, anti-patterns, key file locations

## Architecture

- **[architecture/index.md](./architecture/index.md)** — Architecture Decision Document: strategies, runtimes, adapters, workflows, multi-tenancy
- **[architecture/core-decisions.md](./architecture/core-decisions.md)** — Data, auth, API, frontend, infra decisions and trade-offs
- **[architecture/implementation-patterns.md](./architecture/implementation-patterns.md)** — Naming, structure, API controllers, authorization, anti-patterns
- **[architecture/workflows.md](./architecture/workflows.md)** — Workflow engine: concepts, data models, execution flow, internal tools
- **[architecture/container-runtime.md](./architecture/container-runtime.md)** — Pluggable Docker/K8s runtime + ContainerService refactoring (historical)
- **[architecture/temporal-error-handling.md](./architecture/temporal-error-handling.md)** — Temporal error classification and retry strategy

## System Design

- **[design/tool-execution.md](./design/tool-execution.md)** — Tool execution strategy framework
- **[design/meta-workflow.md](./design/meta-workflow.md)** — Meta-workflow / Aixle Builder design
- **[design/session-config-and-context.md](./design/session-config-and-context.md)** — Session config cascade + context constructor pipeline
- **[design/bmad.md](./design/bmad.md)** — BMAD integration: implemented toggle, system-workflow RFC, and framework reference
- **[design/oauth-unification.md](./design/oauth-unification.md)** — RFC: unified OAuth lifecycle (token broker, MCP OAuth 2.1 discovery/DCR, Temporal refresh sweep, 1MCP evaluation)
- **[design/cloud-connection-security.md](./design/cloud-connection-security.md)** — Customer-facing security notes for connecting an organisation's own Amazon Bedrock account: what the grant allows, where prompts go, the three connect paths and the trust each creates (including the device-code phishing posture), attribution, and what is stored where
- **[design/oauth-implementation.md](./design/oauth-implementation.md)** — As-built OAuth guide: runtime flows, flow engine + `Oauth::State`, MCP discovery (DCR/CIMD) + SSRF doctrine, delivery/refresh/preflight, context.log redaction, agent-CLI auth methods + `/design-login`

## Feature Pipeline

The active workflow: a research report in `research/` feeds a frozen-intent spec in `specs/`, which drives implementation.

- **[research/](./research/)** — Technical research reports + settled design docs, paired per topic (`<topic>-research-<date>.md` + `<topic>-<date>.md`)
  - **[research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md](./research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md)** — Cloud-provider auth for agent CLIs (Bedrock first): connect paths, server-side credential broker, session provisioning. Supersedes the deferred Bedrock/Vertex section of `design/oauth-implementation.md` §9
- **[specs/](./specs/)** — Feature specs: frontmatter (`type`, `created`, `baseline_commit`, `status`, `context`) + Intent / Boundaries / I/O matrix / Tasks / Verification
- **[planning-artifacts/research/](./planning-artifacts/research/)** — BMAD-workflow research reports (same pipeline role as `research/`, produced by the `bmad-technical-research` skill)
  - **[planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md](./planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md)** — Registry-backed MCP connector catalog: Official MCP Registry integration, `server.json` → `MCPServer` mapping, mirror-vs-proxy decision, security posture without an allowlist, phased roadmap
  - **[planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md](./planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md)** — Skills page parity with the connector catalog: skills.sh API reachability (v1 is OIDC-only), mirror-for-browse vs live-search inversion, install-count ranking with measured bulk-publisher inflation, manual `SKILL.md` authoring, CLI-telemetry egress finding, phased roadmap. Includes an addendum from reading the CLI's own source (public audit host, well-known discovery for non-GitHub publishers)
- **[implementation-artifacts/](./implementation-artifacts/)** — BMAD quick-dev specs: frozen-intent block + Code Map / Tasks / Spec Change Log / Verification, plus `deferred-work.md` for findings split out of a spec
  - **[implementation-artifacts/spec-skills-catalog.md](./implementation-artifacts/spec-skills-catalog.md)** — Skills catalog: featured browse, `catalog_skills` mirror with a weekly seeded sweep, manual `SKILL.md` authoring, audit badges
  - **[implementation-artifacts/spec-multi-company-membership.md](./implementation-artifacts/spec-multi-company-membership.md)** — Multi-company membership
  - **[implementation-artifacts/spec-session-terminal-replay.md](./implementation-artifacts/spec-session-terminal-replay.md)** — Session terminal replay

## Strategy

- **[strategy/](./strategy/)** — Business / open-source strategy documents

## Related documentation elsewhere

- `references/aixle-system-reference.md` — agent-facing platform reference (domain model, runtimes, container layout)
- `app/frontend/pages/Docs/data/pages/` — end-user product docs rendered in the app
