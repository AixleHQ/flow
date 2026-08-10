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
- **[design/coder-pool-hardening.md](./design/coder-pool-hardening.md)** — Coder workspace pool + template hardening: why allocation kept handing out one dead box (health never checked, no escape from a bad box, locks aging from acquisition not activity), detached execution for 15–25 min gates, and the template/AMI corrections plus a Collectively-specific template
- **[design/oauth-implementation.md](./design/oauth-implementation.md)** — As-built OAuth guide: runtime flows, flow engine + `Oauth::State`, MCP discovery (DCR/CIMD) + SSRF doctrine, delivery/refresh/preflight, context.log redaction, agent-CLI auth methods + `/design-login`

## Feature Pipeline

The active workflow: a research report in `research/` feeds a frozen-intent spec in `specs/`, which drives implementation.

- **[research/](./research/)** — Technical research reports + settled design docs, paired per topic (`<topic>-research-<date>.md` + `<topic>-<date>.md`)
  - **[research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md](./research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md)** — Cloud-provider auth for agent CLIs (Bedrock first): connect paths, server-side credential broker, session provisioning. Supersedes the deferred Bedrock/Vertex section of `design/oauth-implementation.md` §9
  - **[research/technical-agent-session-log-access-and-control-research-2026-08-10.md](./research/technical-agent-session-log-access-and-control-research-2026-08-10.md)** — Agent session logs: what the tmux `pipe-pane` dual sink already puts on pod stdout and therefore into the cluster's Alloy/Loki stack (verified against staging, with volume measurements), why `SessionLog`/S3 only exists after cleanup, and the design for three personal-MCP additions — `get_session_log` (live `capture-pane` read + stuck verdict), `stop_session`, and a `trigger_task_workflow` that can cancel-then-retrigger the board card's "Run workflow" button
  - **[research/technical-agent-image-size-audit-2026-08-04.md](./research/technical-agent-image-size-audit-2026-08-04.md)** — Agent image bloat audit + as-built fix (`dive` + `docker history` + in-container probes): 1.1–2.4 GB per image was `chmod -R`/`chown -R` layer duplication, plus ~500 MB of verifiably unused content (Playwright headless-shell, Mesa/LLVM/Xvfb). Implemented on `fix/agent-image-slim`: 5.35 → 2.09 GB (`claude-code`), the `AGENT_BROWSERS_GROUP` replacement for the 1 GB-duplicating recursive chown, the build-time browser probe, and the end-to-end session/workflow verification
- **[specs/](./specs/)** — Feature specs: frontmatter (`type`, `created`, `baseline_commit`, `status`, `context`) + Intent / Boundaries / I/O matrix / Tasks / Verification
- **[planning-artifacts/research/](./planning-artifacts/research/)** — BMAD-workflow research reports (same pipeline role as `research/`, produced by the `bmad-technical-research` skill)
  - **[planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md](./planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md)** — Registry-backed MCP connector catalog: Official MCP Registry integration, `server.json` → `MCPServer` mapping, mirror-vs-proxy decision, security posture without an allowlist, phased roadmap
  - **[planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md](./planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md)** — Skills page parity with the connector catalog: skills.sh API reachability (v1 is OIDC-only), mirror-for-browse vs live-search inversion, install-count ranking with measured bulk-publisher inflation, manual `SKILL.md` authoring, CLI-telemetry egress finding, phased roadmap. Includes an addendum from reading the CLI's own source (public audit host, well-known discovery for non-GitHub publishers)
  - **[planning-artifacts/research/technical-mcp-oauth-discovery-in-the-wild-research-2026-08-07.md](./planning-artifacts/research/technical-mcp-oauth-discovery-in-the-wild-research-2026-08-07.md)** — What the catalog's remote MCP servers actually support for OAuth, measured over 178 hosts: Vercel's DCR approves loopback callbacks only (root cause of "couldn't connect"), DCR advertised by 96% but advertisement ≠ acceptance, CIMD at 20%, device flow at 9%, plus two bugs of ours — a probe shape that loses `WWW-Authenticate` on a fifth of hosts, and a protected-resource fallback that is not RFC 9728 path-aware
- **[implementation-artifacts/](./implementation-artifacts/)** — BMAD quick-dev specs: frozen-intent block + Code Map / Tasks / Spec Change Log / Verification, plus `deferred-work.md` for findings split out of a spec
  - **[implementation-artifacts/spec-skills-catalog.md](./implementation-artifacts/spec-skills-catalog.md)** — Skills catalog: featured browse, `catalog_skills` mirror with a weekly seeded sweep, manual `SKILL.md` authoring, audit badges
  - **[implementation-artifacts/spec-multi-company-membership.md](./implementation-artifacts/spec-multi-company-membership.md)** — Multi-company membership
  - **[implementation-artifacts/spec-session-observability-mcp-tools.md](./implementation-artifacts/spec-session-observability-mcp-tools.md)** — Session observability and control over the personal MCP: `list_sessions`, `get_session_log` (live `capture-pane` read + idle time + quota verdict), `stop_session`, `trigger_task_workflow` with cancel-then-retrigger
  - **[implementation-artifacts/spec-session-terminal-replay.md](./implementation-artifacts/spec-session-terminal-replay.md)** — Session terminal replay
  - **[implementation-artifacts/40-1-workflow-builder-ux-redesign.md](./implementation-artifacts/40-1-workflow-builder-ux-redesign.md)** — Workflow builder full UX redesign (story 40.1, shipped): tab layout, step editor sections, Base Resources move. Older BMAD story format, moved here from the retired `ai/` tree

## Strategy

- **[strategy/](./strategy/)** — Business / open-source strategy documents

## Legal

- **[legal/TERMS_OF_SERVICE.md](./legal/TERMS_OF_SERVICE.md)** — Aixle Flow Terms of Service; published verbatim at `/terms-of-service` (`app/views/web/pages/terms_of_service.html.erb`)
- **[legal/PRIVACY_POLICY.md](./legal/PRIVACY_POLICY.md)** — Aixle Flow Privacy Policy; published verbatim at `/privacy-policy` (`app/views/web/pages/privacy_policy.html.erb`)

## Related documentation elsewhere

- `references/aixle-system-reference.md` — agent-facing platform reference (domain model, runtimes, container layout)
- `app/frontend/pages/Docs/data/pages/` — end-user product docs rendered in the app
