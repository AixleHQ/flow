# Documentation Index

**Project:** Aixle

All architecture, design, research, and strategy docs live under `docs/`. Whenever
a document is added, removed, or moved here, update this index in the same change
(see CLAUDE.md).

---

## Project

- **[project/overview.md](./project/overview.md)** — Executive summary, tech stack, architecture overview, data model, API structure
- **[project/context.md](./project/context.md)** — LLM-optimized rules: tech stack, patterns, anti-patterns, key file locations
- **[project/worktree-stack.md](./project/worktree-stack.md)** — Running a second, isolated Compose stack from a git worktree: the variables that keep its network, image, ports and database off the default stack's, and what still bites (Google sign-in, the test flock, two Traefiks on one socket)

## Architecture

- **[architecture/index.md](./architecture/index.md)** — Architecture Decision Document: strategies, runtimes, adapters, workflows, multi-tenancy
- **[architecture/core-decisions.md](./architecture/core-decisions.md)** — Data, auth, API, frontend, infra decisions and trade-offs
- **[architecture/implementation-patterns.md](./architecture/implementation-patterns.md)** — Naming, structure, API controllers, authorization, anti-patterns
- **[architecture/workflows.md](./architecture/workflows.md)** — Workflow engine: concepts, data models, execution flow, internal tools
- **[architecture/container-runtime.md](./architecture/container-runtime.md)** — Pluggable Docker/K8s runtime + ContainerService refactoring (historical)
- **[architecture/temporal-error-handling.md](./architecture/temporal-error-handling.md)** — Temporal error classification and retry strategy
- **[architecture/temporal-versioning.md](./architecture/temporal-versioning.md)** — Changing workflow code safely: what needs `patched`, the patches in use, the recorded-history replay test, workflow task failure reporting

## System Design

- **[design/tool-execution.md](./design/tool-execution.md)** — Tool execution strategy framework
- **[design/meta-workflow.md](./design/meta-workflow.md)** — Aixle Builder: the original meta-workflow design, with a note on what ships (an interactive session served the personal MCP tools pinned to its project) and how its tools are authorized
- **[design/session-config-and-context.md](./design/session-config-and-context.md)** — Session config cascade + context constructor pipeline
- **[design/bmad.md](./design/bmad.md)** — BMAD integration: implemented toggle, system-workflow RFC, and framework reference
- **[design/oauth-unification.md](./design/oauth-unification.md)** — RFC: unified OAuth lifecycle (token broker, MCP OAuth 2.1 discovery/DCR, Temporal refresh sweep, 1MCP evaluation)
- **[design/federated-identity.md](./design/federated-identity.md)** — RFC: federated identity, SSO and organization-level auth policy. Providers and policy as two tables (so a deployment-wide Google client and a per-customer OIDC connection can coexist), enforcement at company entry with appending session proofs and step-up rather than sign-out, identity bound to `(provider, subject)` with a promotion gate that closes the email-join-key takeover vector, the case for dropping SAML entirely rather than linking `ruby-saml` or running a sidecar, expand/contract cutover, the case against adopting Keycloak as the primary IdP, and a screenshot walkthrough of the shipped surfaces. Invariants live in the companion architecture spine
- **[design/cloud-connection-security.md](./design/cloud-connection-security.md)** — Customer-facing security notes for connecting an organisation's own Amazon Bedrock account: what the grant allows, where prompts go, the three connect paths and the trust each creates (including the device-code phishing posture), attribution, and what is stored where
- **[design/coder-pool-hardening.md](./design/coder-pool-hardening.md)** — Coder workspace pool + template hardening: why allocation kept handing out one dead box (health never checked, no escape from a bad box, locks aging from acquisition not activity), detached execution for 15–25 min gates, and the template/AMI corrections plus a Collectively-specific template
- **[design/oauth-implementation.md](./design/oauth-implementation.md)** — As-built OAuth guide: runtime flows, flow engine + `Oauth::State`, MCP discovery (DCR/CIMD) + SSRF doctrine, delivery/refresh/preflight, context.log redaction, agent-CLI auth methods + `/design-login`
- **[design/session-admission-queue/](./design/session-admission-queue/)** — Durable session admission queues: PostgreSQL owns the queue, permits and policy; Temporal owns execution; the runtime supplies resource facts
  - **[design/session-admission-queue/ARCHITECTURE-SPINE.md](./design/session-admission-queue/ARCHITECTURE-SPINE.md)** — The invariants (AD-1…AD-10): one applicable pool, atomic FIFO, durable launch intent, "unknown creation retains capacity", confirmed release, separate waiting and execution clocks
  - **[design/session-admission-queue/TECH-DESIGN.md](./design/session-admission-queue/TECH-DESIGN.md)** — The reasoning behind them: inspected baseline behaviour, limit selection, data model, runtime idempotency, capacity waiting, alternatives and open decisions
  - **[design/session-admission-queue/ROLLOUT.md](./design/session-admission-queue/ROLLOUT.md)** — Operator runbook: deployment settings read live, the drain-gated cutover, pause/resume and recovery
  - **[design/session-admission-queue/reviews/](./design/session-admission-queue/reviews/)** — Design-phase review records (invariants, evidence, coverage, editorial) kept alongside the contract they checked
- **[design/azure-devops-integration.md](./design/azure-devops-integration.md)** — Azure DevOps integration: Entra service-principal auth with approved organization installations, GUID-based repository identity, session Git via a derived-key credential endpoint, PR/Boards agent tools, and a phased CI/webhook parity extension
- **[design/entity-versioning.md](./design/entity-versioning.md)** — RFC: version history, diff and revert for workflows (with steps and sub-steps), agents, skills, custom tools and MCP servers; explicit Save replaces builder autosave, delete becomes archive, runs and sessions record the versions they launched with; hazards (MCP secrets, Shrine tool files, hard-deleted steps) and a phased plan
- **[design/grok-runtime-integration.md](./design/grok-runtime-integration.md)** — Grok (xAI) runtime decisions: the official `@xai-official/grok` CLI, device-code auth with `~/.grok/auth.json` as the credential, model catalogue + pricing from `/v1/language-models`, and why usage comes from the MITM log rather than OTLP

## Feature Pipeline

The active workflow: a research report in `research/` feeds a frozen-intent spec in `specs/`, which drives implementation.

- **[design/agent-credential-lifecycle.md](./design/agent-credential-lifecycle.md)** — Strategy for agent-CLI credentials across all seven runtimes: per-runtime refresh coverage, the measured production root cause (idle `ready` sessions pin a credential out of the refresh sweep), a declared lifecycle contract per adapter, container↔server read-through (write-back, push, lease), refresh observability, and the image/CLI freshness programme
- **[research/](./research/)** — Technical research reports + settled design docs, paired per topic (`<topic>-research-<date>.md` + `<topic>-<date>.md`)
  - **[research/technical-federated-identity-and-sso-provider-research-2026-09-16.md](./research/technical-federated-identity-and-sso-provider-research-2026-09-16.md)** — Market scan for broad login coverage (Microsoft/Entra, generic OIDC, enterprise SAML, passkeys, MFA, magic links, SCIM) against three constraints: SSO must work for self-hosters, no deadline, no paid dependency in the login path. Evaluates Keycloak on its merits and against this codebase, eliminates the commercial CIAM market and the AGPL/paywalled OSS IdPs with citations, documents the five Critical `ruby-saml` auth-bypass advisories in 15 months, and recommends keeping the org model and login page in Rails while brokering SAML/SCIM to an Apache-2.0 Ory Polis sidecar — plus the email-as-join-key takeover risk and the missing server-side session record, which are requirements regardless of the choice. The sidecar half of that recommendation was later dropped (see the RFC §4.5 and AD-28): SCIM is served in-process and SAML not at all
  - **[research/technical-container-token-brokering-research-2026-09-05.md](./research/technical-container-token-brokering-research-2026-09-05.md)** — Can agent containers be given short-lived access tokens instead of the user's OAuth refresh token? Written after the 2026-09-05 credential incident: why the multi-holder rotation race exists, the ToS constraint that decides the question before the technical one does, Claude Code's actual credential precedence and `apiKeyHelper` mechanics, the AWS `credential_process` broker we already run as the precedent, and the four staging probes that must run before anything is built
  - **[research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md](./research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md)** — Cloud-provider auth for agent CLIs (Bedrock first): connect paths, server-side credential broker, session provisioning. Supersedes the deferred Bedrock/Vertex section of `design/oauth-implementation.md` §9
  - **[research/technical-agent-session-log-access-and-control-research-2026-08-10.md](./research/technical-agent-session-log-access-and-control-research-2026-08-10.md)** — Agent session logs: what the tmux `pipe-pane` dual sink already puts on pod stdout and therefore into the cluster's Alloy/Loki stack (verified against staging, with volume measurements), why `SessionLog`/S3 only exists after cleanup, and the design for three personal-MCP additions — `get_session_log` (live `capture-pane` read + stuck verdict), `stop_session`, and a `trigger_task_workflow` that can cancel-then-retrigger the board card's "Run workflow" button
  - **[research/technical-codex-workspace-trust-prompt-2026-08-14.md](./research/technical-codex-workspace-trust-prompt-2026-08-14.md)** — Why a Codex `non_interactive` workflow step can wedge on "Do you trust the contents of this directory?" (task #605): measured against the real CLI 0.147.0 in a tmux harness with a fresh `CODEX_HOME` per run — `--yolo` does not cover the dialog, the trust entry was being lost by the `config.toml` read-modify-write in the MCP append (corruption that still parses wedges; corruption that breaks TOML exits loudly), and the as-built fix — an argv `-c` trust override, an append that refuses to overwrite what it could not read, and pane-based fail-fast detection inside the existing per-minute sweep
  - **[research/technical-agent-image-size-audit-2026-08-04.md](./research/technical-agent-image-size-audit-2026-08-04.md)** — Agent image bloat audit + as-built fix (`dive` + `docker history` + in-container probes): 1.1–2.4 GB per image was `chmod -R`/`chown -R` layer duplication, plus ~500 MB of verifiably unused content (Playwright headless-shell, Mesa/LLVM/Xvfb). Implemented on `fix/agent-image-slim`: 5.35 → 2.09 GB (`claude-code`), the `AGENT_BROWSERS_GROUP` replacement for the 1 GB-duplicating recursive chown, the build-time browser probe, and the end-to-end session/workflow verification
- **[specs/](./specs/)** — Feature specs: frontmatter (`type`, `created`, `baseline_commit`, `status`, `context`) + Intent / Boundaries / I/O matrix / Tasks / Verification. A `spec-<slug>/` **folder** instead holds a BMAD spec kernel — `SPEC.md` (Why / Capabilities / Constraints / Non-goals / Success signal) derived from an append-only `.memlog.md`, with its invariants adopted from a companion rather than restated. Both shapes are live; the folder shape is produced and updated only by the `bmad-spec` skill
  - **[specs/spec-federated-identity/](./specs/spec-federated-identity/)** — Federated identity and SSO: five capabilities from foundation (multi-identity users, revocable sessions) through company auth policy, Microsoft/OIDC, passwordless and directory provisioning — CAP-5 (enterprise SAML) was built, measured and removed. Companions: the [architecture spine](./planning-artifacts/architecture/architecture-federated-identity-2026-09-17/ARCHITECTURE-SPINE.md) (invariants + diagrams) and the [RFC](./design/federated-identity.md) (audit, phasing, declined alternatives)
- **[planning-artifacts/architecture/](./planning-artifacts/architecture/)** — BMAD architecture spines: the terse invariant contract (`AD-n` blocks with Binds / Prevents / Rule) a feature's epics are built from, plus the run's append-only `.memlog.md` and its reviewer-gate output. Produced by the `bmad-architecture` skill; the human-facing companion lives in `design/`
  - **[planning-artifacts/architecture/architecture-federated-identity-2026-09-17/](./planning-artifacts/architecture/architecture-federated-identity-2026-09-17/)** — Federated identity and SSO: 28 ADs covering the provider/policy split, company-entry enforcement with appending session proofs, identity binding and assertion-to-row binding, expand/contract cutover, and the no-stranding policy guard. AD-8 and AD-9 (the SAML sidecar) are retired by AD-28, which drops SAML entirely. Companion: [design/federated-identity.md](./design/federated-identity.md)
- **[planning-artifacts/research/](./planning-artifacts/research/)** — BMAD-workflow research reports (same pipeline role as `research/`, produced by the `bmad-technical-research` skill)
  - **[planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md](./planning-artifacts/research/technical-mcp-connector-catalog-research-2026-08-01.md)** — Registry-backed MCP connector catalog: Official MCP Registry integration, `server.json` → `MCPServer` mapping, mirror-vs-proxy decision, security posture without an allowlist, phased roadmap
  - **[planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md](./planning-artifacts/research/technical-skills-catalog-featured-and-manual-add-research-2026-08-03.md)** — Skills page parity with the connector catalog: skills.sh API reachability (v1 is OIDC-only), mirror-for-browse vs live-search inversion, install-count ranking with measured bulk-publisher inflation, manual `SKILL.md` authoring, CLI-telemetry egress finding, phased roadmap. Includes an addendum from reading the CLI's own source (public audit host, well-known discovery for non-GitHub publishers)
  - **[planning-artifacts/research/technical-mcp-oauth-discovery-in-the-wild-research-2026-08-07.md](./planning-artifacts/research/technical-mcp-oauth-discovery-in-the-wild-research-2026-08-07.md)** — What the catalog's remote MCP servers actually support for OAuth, measured over 178 hosts: Vercel's DCR approves loopback callbacks only (root cause of "couldn't connect"), DCR advertised by 96% but advertisement ≠ acceptance, CIMD at 20%, device flow at 9%, plus two bugs of ours — a probe shape that loses `WWW-Authenticate` on a fifth of hosts, and a protected-resource fallback that is not RFC 9728 path-aware
  - **[planning-artifacts/research/technical-kiro-cli-as-a-platform-agent-runtime-research-2026-08-28.md](./planning-artifacts/research/technical-kiro-cli-as-a-platform-agent-runtime-research-2026-08-28.md)** — Adding Kiro CLI as the seventh agent runtime: the permitted-use terms now name the CLI and CI/CD automation explicitly (partly reversing the 2026-07-24 Bedrock doc's disqualification), device-code login, credentials in SQLite rather than JSON (and why a file-presence watcher on it closes the auth container early), credits instead of `cost_cents`, the complete touch-point checklist, a generalized "add any new agent runtime" playbook, and as-built appendices (2.65 GB image after removing a 1.4 GB layer duplication; the private CodeWhisperer-lineage catalogue/usage APIs the adapter now calls directly; session cost as a credit delta; v3 engine and the prompts that must be pre-answered)
- **[implementation-artifacts/](./implementation-artifacts/)** — BMAD quick-dev specs: frozen-intent block + Code Map / Tasks / Spec Change Log / Verification, plus `deferred-work.md` for findings split out of a spec
  - **[implementation-artifacts/spec-skills-catalog.md](./implementation-artifacts/spec-skills-catalog.md)** — Skills catalog: featured browse, `catalog_skills` mirror with a weekly seeded sweep, manual `SKILL.md` authoring, audit badges
  - **[implementation-artifacts/spec-multi-company-membership.md](./implementation-artifacts/spec-multi-company-membership.md)** — Multi-company membership
  - **[implementation-artifacts/spec-session-observability-mcp-tools.md](./implementation-artifacts/spec-session-observability-mcp-tools.md)** — Session observability and control over the personal MCP: `list_sessions`, `get_session_log` (live `capture-pane` read + idle time + quota verdict), `stop_session`, `trigger_task_workflow` with cancel-then-retrigger
  - **[implementation-artifacts/spec-session-config-item-access.md](./implementation-artifacts/spec-session-config-item-access.md)** — Config items as an attachable session/workflow/step resource + `get_config_item` over the session MCP: MCP-only delivery (why not env, why not a file), the attached-set-not-project-set rule, `config_item_accesses` audit trail, and the value-level redaction pipeline with the one sink it cannot reach (pod stdout → Loki)
  - **[implementation-artifacts/spec-session-terminal-replay.md](./implementation-artifacts/spec-session-terminal-replay.md)** — Session terminal replay
  - **[implementation-artifacts/spec-session-admission-queue.md](./implementation-artifacts/spec-session-admission-queue.md)** — Session admission queue: frozen intent, code map and verification for the implementation of `design/session-admission-queue/`
  - **[implementation-artifacts/review-session-queue-blind.md](./implementation-artifacts/review-session-queue-blind.md)** / **[review-session-queue-edges.md](./implementation-artifacts/review-session-queue-edges.md)** — The two independent review briefs commissioned for the admission-queue implementation (a blind correctness pass and an edge-case pass), kept so a later reviewer can see what was asked for
  - **[implementation-artifacts/40-1-workflow-builder-ux-redesign.md](./implementation-artifacts/40-1-workflow-builder-ux-redesign.md)** — Workflow builder full UX redesign (story 40.1, shipped): tab layout, step editor sections, Base Resources move. Older BMAD story format, moved here from the retired `ai/` tree

## Product

- **[product/user-guide-outline.md](./product/user-guide-outline.md)** — Outline of the end-user product guide: the board → workflow → agent → results loop, section-by-section skeleton following the product sidebar, two end-to-end stories, terminology notes
- **[product/changelog-product-areas.md](./product/changelog-product-areas.md)** — Frozen user-facing product map used as the changelog taxonomy: named product areas, changelog rules, area → guide-chapter map, snapshot baseline

## Operator documentation

The repository mirror of the in-app portal served at `/docs`
(`app/frontend/pages/Docs/data/pages/`). Written for people installing and
running Flow — the product-level guide outlined above is a separate document set.

- **[user-guide/index.md](./user-guide/index.md)** — Entry point: the board → workflow → agent loop and the mental model
- **[user-guide/board.md](./user-guide/board.md)** — Projects, columns, cards, and column → workflow bindings
- **[user-guide/workflows.md](./user-guide/workflows.md)** — DAG steps, retries, approval gates, parallel runs
- **[user-guide/agents.md](./user-guide/agents.md)** — Personas, the container, and how session context is built
- **[user-guide/runtimes.md](./user-guide/runtimes.md)** — The seven agent CLIs, their images, credentials, and where each one's usage and cost come from
- **[user-guide/tools.md](./user-guide/tools.md)** — Tool kinds, execution modes, built-in board tools, resource resolution
- **[user-guide/mcp.md](./user-guide/mcp.md)** — MCP transports, the internal `aixle-tools` server, config-item credentials
- **[user-guide/integrations.md](./user-guide/integrations.md)** — GitHub, GitLab, Linear, Google OAuth, and webhooks
- **[user-guide/azure-devops.md](./user-guide/azure-devops.md)** — Connecting an Azure DevOps organization end to end: what differs between SaaS and self-hosted, the one Entra step in the customer directory, the three personal-access-token scopes and what each is spent on, choosing Azure projects and widening that set later
- **[user-guide/session-queues.md](./user-guide/session-queues.md)** — Why a session waits: every combination of project limit and installation ceiling, how a reservation differs from a cap, what is exempt from the queue altogether, and the operator knobs behind it
- **[user-guide/configuration.md](./user-guide/configuration.md)** — Env vars, OAuth, agent credentials, and other knobs
- **[operations/azure-devops-app-registration.md](./operations/azure-devops-app-registration.md)** — Operator runbook: register the Entra application, give it a credential, and publish the client ID. Customers bind their own organizations from inside Flow by proving they administer them
- **[quickstart.md](./quickstart.md)** — Get a local instance running and see one card move
- **[reference/index.md](./reference/index.md)** — Reference set: [API](./reference/api.md), [CLI](./reference/cli.md), [configuration](./reference/configuration.md)

## Strategy

- **[strategy/](./strategy/)** — Business / open-source strategy documents

## Legal

- **[legal/TERMS_OF_SERVICE.md](./legal/TERMS_OF_SERVICE.md)** — Aixle Flow Terms of Service; published verbatim at `/terms-of-service` (`app/views/web/pages/terms_of_service.html.erb`)
- **[legal/PRIVACY_POLICY.md](./legal/PRIVACY_POLICY.md)** — Aixle Flow Privacy Policy; published verbatim at `/privacy-policy` (`app/views/web/pages/privacy_policy.html.erb`)

## Related documentation elsewhere

- `references/aixle-system-reference.md` — agent-facing platform reference (domain model, runtimes, container layout)
- `app/frontend/pages/Docs/data/pages/` — the markdown the `/docs` portal renders; mirrored in this tree under [user-guide/](./user-guide/) and [reference/](./reference/). Sections:
  **Using Flow** (the product guide: what a user does on each screen) and **User guide /
  Reference** (operator material: install, runtimes, MCP, API). Adding a page there means
  registering it in `navStructure.ts`, `data/pages/index.ts`, `data/searchIndex.ts`, and the
  allow-list in `Web::DocsController`
