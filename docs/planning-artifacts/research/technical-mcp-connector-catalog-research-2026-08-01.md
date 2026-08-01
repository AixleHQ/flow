---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'MCP connector catalog — registry-backed, one-click MCP server installs for Aixle projects'
research_goals: 'Decide which public MCP registry to integrate with, how to normalize its manifest into our existing MCPServer model, and what the install/verification/security contract should be'
user_name: 'Artem_petrov'
date: '2026-08-01'
web_research_enabled: true
source_verification: true
---

# Borrowing the Connector: Registry-Backed MCP Installs for Aixle

**Date:** 2026-08-01
**Author:** Artem_petrov
**Research Type:** technical

---

## Research Overview

Aixle can already *run* MCP servers well — OAuth with dynamic client registration, encrypted and masked credentials, per-user credential scoping, and config emission across three agent CLIs. What it cannot do is help anyone *find* one. Adding an MCP server today means knowing a URL or an npm package name and typing raw transport config into a form. Meanwhile the skills feature has the opposite shape: a searchable registry, one-click install, provenance recorded on the row. This research asks whether the MCP half can be given the same acquisition path — the concept AWS Quick Suite ships as "connections," and the reason a user can add Zoom or Salesforce there without knowing what a transport is.

The answer is yes, and the enabling fact is that the Official MCP Registry publishes a machine-readable setup manifest. Its `server.json` schema (version `2025-12-11`) declares, per connector, exactly which inputs a user must supply — with `isRequired`, `isSecret`, `format`, `choices`, and defaults attached to each. That maps onto Aixle's existing `headers` / `env` / `args` columns with no new concepts, which means a generated install form is a rendering problem rather than a data-model problem. Two further findings cut the projected cost: the `mcp` gem already in this project's bundle (1.0.0) ships a full client, so install-time verification is wiring rather than construction; and stdio execution is already plumbed through all three agent adapters, so package-based connectors need field-filling, not new machinery.

Two findings pushed against the initial plan and changed the design. First, the registry's `search` parameter is a **substring match on server name only** — verified in both the OpenAPI specification and a live probe — so a thin live-proxy catalog would return nothing for "issue tracker" or "CRM"; usable search requires a local mirror, which is also precisely what the registry instructs aggregators to build, given it disclaims uptime and durability guarantees and remains in preview. Second, the MCP `2026-07-28` specification, released four days before this research, deprecates Dynamic Client Registration in favour of Client ID Metadata Documents — the mechanism Aixle's OAuth discovery is built on. It is not urgent (the compatibility window is open and explicit), but it is now a tracked follow-up rather than an unknown. The full findings, decisions, and phased roadmap follow; the executive summary below is the short version.

---

## Executive Summary

Aixle should add a registry-backed connector catalog to its MCP feature by mirroring the Official MCP Registry locally, rendering install forms from the registry's own declared input metadata, and recording provenance on the existing `MCPServer` row. The work is additive: nothing downstream of the model changes, the manual entry form remains first-class, and if the upstream registry is down, reset, or flag-disabled, the product degrades exactly to today's behaviour.

The security posture is the part that needed the most deliberate thought, because a decision was taken early to **allow every server in the registry, with no allowlist** — justified on the grounds that the agent container is already an arbitrary-code-execution environment, so restricting MCP packages while leaving `npx` and `pip` open would be theatre. That decision holds, but it shifts the entire defensive burden onto two controls that must therefore actually be built: pinning the exact resolved version in the emitted command, and snapshotting the manifest and tool set at install so drift can be detected later. The second control cannot be delegated to the agent clients — Claude Code, Claude's desktop and mobile apps, and OpenAI Codex all have open, documented failures to honour `notifications/tools/list_changed`. If Aixle wants rug-pull detection, Aixle owns it.

The phasing follows the risk gradient rather than the feature list. Remote HTTPS connectors first (no new code execution, and most first-party vendor connectors are remote), then package/stdio installs, then verification and drift detection, then an update path. The largest genuine cost is frontend work on the generated form; under-investing there produces a catalog whose installs users must repair by hand, which is worse than shipping no catalog at all.

**Key Technical Findings:**

- **`server.json` already encodes the setup contract.** `isRequired` / `isSecret` / `format` / `choices` / `default` / `placeholder` per input, across `remotes[].headers`, `packages[].environmentVariables`, and both argument forms. The schema also refuses version ranges and `latest` outright.
- **🔴 Registry search is name-substring only.** Confirmed by OpenAPI text and live probe. This alone invalidates a thin live-proxy design and forces a local mirror — which the registry documentation independently prescribes ("scrape... once per hour, and persist the data in their own data store"), since it "does not provide uptime or data durability guarantees" and is in preview where "data resets may occur."
- **🔴 DCR is deprecated as of the `2026-07-28` spec**, superseded by Client ID Metadata Documents, with backwards compatibility maintained and removal slated for a future version. `Mcp::OauthDiscoveryService` is a DCR implementation.
- **🟢 The MCP client is already vendored.** `gem "mcp"` 1.0.0 provides `MCP::Client#list_tools`, `MCP::Client::HTTP`, and a full OAuth provider stack (discovery, PKCE, storage-backed, client-credentials, JWT assertion).
- **🟢 stdio is already plumbed.** `base_adapter.rb:215/242` plus all three agent adapters already emit `command`/`args`/`env`; per-server env scoping means no credential bleed to fix; exact-version pinning is already established practice (`base_adapter.rb:232-253`, issue #340).
- **Verification is asymmetric and must be disclosed honestly.** `tools/list` probing works for `remotes[]` but is impossible server-side for `packages[]` without executing untrusted code on our infrastructure — which is out of scope by decision.
- **Scale is a non-issue.** ~9,652 servers (~28,959 with versions) as of May 2026; the mirror is tens of thousands of small, disposable, rebuildable rows.
- **No prior art to copy.** Claude Code, VS Code, and Cursor all expose MCP installs as hand-edited JSON. A manifest-driven install form is a differentiation opening, not a solved pattern.

**Technical Recommendations:**

1. **Mirror the registry; fetch live at install.** Browse and search from a local Postgres mirror synced hourly via `updated_since`; re-fetch the exact manifest from `/v0.1/servers/{name}/versions/{version}` at the moment of install so no install is built from stale data.
2. **One table, optional provenance, no foreign key.** Add three nullable columns to `mcp_servers` (`connector_name`, `connector_version`, `connector_manifest`). Never FK to the mirror — mirrored rows legitimately disappear under moderation, and an install must outlive its catalog entry.
3. **Pin exact versions and snapshot declarations.** The emitted command carries the resolved version; the snapshot stores input *declarations* and the observed tool set, never secret *values*.
4. **Phase by risk:** remotes → packages/stdio → verification and drift → update path. Park CIMD migration, subregistry mode, and Smithery as a second source, each with its reason recorded.
5. **Never imply a check that did not happen.** A "verified" badge on an unprobed stdio install would undermine the entire security rationale for allowing everything.

---

## Table of Contents

1. [Research Overview](#research-overview)
2. [Executive Summary](#executive-summary)
3. [Technical Research Scope Confirmation](#technical-research-scope-confirmation) — problem framing, six binding constraints
4. [Technology Stack Analysis](#technology-stack-analysis) — registry landscape, `server.json` schema, API surface, packaging targets, threat trends
5. [Integration Patterns Analysis](#integration-patterns-analysis) — the `server.json` → `MCPServer` mapping, transports, authorization, secrets, verification, coexistence with manual entry
6. [Architectural Patterns and Design](#architectural-patterns-and-design) — the data-plane decision, design invariants, scalability, security architecture, data model, operations
7. [Implementation Approaches and Technology Adoption](#implementation-approaches-and-technology-adoption) — tooling, testing doctrine, operations, risk table
8. [Technical Research Recommendations](#technical-research-recommendations) — roadmap, stack, skills, success metrics
9. [Future Technical Outlook](#future-technical-outlook) — protocol and registry trajectory
10. [Research Methodology and Source Verification](#research-methodology-and-source-verification) — sources, queries, confidence, limitations
11. [Appendix: Decision Log](#appendix-decision-log)
12. [Conclusion and Next Steps](#conclusion-and-next-steps)

---

## Technical Research Scope Confirmation

**Research Topic:** MCP connector catalog — registry-backed, one-click MCP server installs for Aixle projects

**Research Goals:** Decide which public MCP registry to integrate with, how to normalize its manifest into our existing `MCPServer` model, and what the install / verification / security contract should be.

**Problem framing.** Aixle already has two resource acquisition patterns that sit at opposite ends of a spectrum:

| | Catalog | Declared setup inputs | Runtime |
|---|---|---|---|
| `Skill` | Yes — `SkillsRegistryService` search + install against skills.sh | Not needed | `npx skills add` at session start |
| `MCPServer` | **No** — hand-typed form only | **No** | Mature: OAuth + DCR, encrypted `headers`/`env`, `ConfigItem` substitution, per-user credentials, `.mcp.json` emission in all three agent adapters |

The MCP runtime is already strong; what is missing is the *acquisition* half. AWS Quick Suite's "connections" concept is the reference point: a catalog of pre-described integrations where the user fills a generated form (URL, credentials, options) instead of authoring raw transport config.

**Technical Research Scope:**

- Architecture Analysis — registry data models, manifest schemas, catalog/subregistry topology
- Implementation Approaches — live API proxy vs local mirror, install pipeline, verification
- Technology Stack — registries, manifest schema versions, packaging ecosystems, runtime targets
- Integration Patterns — manifest inputs → `headers`/`env`/`args` mapping, OAuth/DCR, `ConfigItem` reuse
- Performance Considerations — registry availability, caching, sync cadence, version drift

**Explicit constraints carried into the research (decided before it started):**

1. **Project scope only.** Catalog metadata is global and read-only; installs are project-scoped, matching the current `MCPServer` model. No company-level connector scope in v1.
2. **Permissions unchanged.** `MCPServersPolicy#create? = project_writable?` already means "any member with write access". No new policy objects.
3. **No self-hosting of MCP servers.** Aixle already launches processes (node, python) inside the agent container; standing up a separate MCP-hosting sidecar/pod tier is out of scope.
4. **No allowlist — everything installable.** The agent container is already an arbitrary-code-execution environment, so gating MCP packages while leaving `npx`/`pip` open would be theatre. Security is therefore addressed by *pinning and change-detection*, not by restricting the catalog.
5. **Manual entry must survive.** The existing hand-authored MCP server form stays as a first-class path. The catalog is strictly additive — anything not in a registry, plus private/internal endpoints, must remain addable by hand.
6. **No seed files.** Discovery goes through the registry API; a small "featured" set may be pinned in code for the empty state.

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Live API probing of candidate registries in addition to documentation review

**Scope Confirmed:** 2026-08-01

---

## Technology Stack Analysis

### Registry Landscape

Four candidate catalogs exist, with materially different value propositions. Only the first is a neutral protocol-level registry; the rest are commercial or vendor products layered on top.

**Official MCP Registry** — `https://registry.modelcontextprotocol.io`. Community-driven, run by the MCP project itself. Unauthenticated read-only REST API; publishing requires namespace-proving authentication. It is explicitly a *metadata* registry: it hosts no code and runs no servers. It positions downstream consumers as "aggregators" and expects them to scrape and persist data locally. Critically, the project states the registry **"does not provide uptime or data durability guarantees"** and is **"currently in preview,"** where "breaking changes or data resets may occur before general availability."
_Confidence: High — stated in first-party documentation and confirmed by live API probes._
_Source: https://modelcontextprotocol.io/registry/registry-aggregators_

**Smithery** — `smithery.ai`. Commercial registry + gateway + hosting. Reported as a ~6,000-server catalog with one-command installs and Smithery-hosted remote endpoints requiring no infrastructure from the consumer. Its registry search exposes richer ranking signals than the official registry: `verified`, `remote`, `isDeployed`, `useCount`, `homepage`, `owner`, `namespace`, `score`. Server configuration is declared as a Zod-derived `configSchema`.
_Relevance to Aixle: strong as a **metadata quality** source (better ranking signals, richer config schema); rejected as a **runtime**, because Smithery-hosted endpoints mean customer credentials transit a third party — unacceptable for the managed/enterprise posture, and not topology-neutral for OSS self-hosting._
_Confidence: Medium — figures come from third-party reviews rather than first-party docs; the `configSchema` mechanism is first-party documented._
_Sources: https://smithery.ai/docs/build/deployments/typescript, https://clawnewbie.com/tools/smithery_

**Docker MCP Catalog / MCP Toolkit** — curated collection from verified publishers (Stripe, Elastic, Grafana, GitHub), 200+ servers, distributed as containers through Docker Desktop. Each server runs in its own container with no host access unless explicitly granted; a Secret Engine stores PATs/OAuth tokens and injects them into containers at runtime; an MCP Gateway handles lifecycle, routing, and security checks on both tool calls and outputs.
_Relevance to Aixle: the **curation and secret-injection model** is the closest existing analogue to what we want, but the distribution mechanism is Docker Desktop-bound and the catalog is far smaller than the open registry. Not a v1 integration target; a useful design reference._
_Confidence: High — first-party Docker documentation._
_Sources: https://docs.docker.com/ai/mcp-catalog-and-toolkit/catalog/, https://www.docker.com/blog/introducing-docker-mcp-catalog-and-toolkit/_

**GitHub MCP Registry** — GitHub's own discovery surface for finding, installing, and managing MCP servers. Overlaps with the official registry's `io.github.*` namespace rather than competing on schema.
_Confidence: Medium — described in GitHub's blog; relationship to the official registry's data set not fully pinned down in this pass._
_Source: https://github.blog/ai-and-ml/generative-ai/how-to-find-install-and-manage-mcp-servers-with-the-github-mcp-registry/_

**Scraped list sites** (mcp.so, PulseMCP, Glama, tooldirectory) — aggregate names and links but do not expose a normalized, machine-consumable input schema. Not viable as an install source.
_Confidence: Medium._

**Assessment:** the Official MCP Registry is the only vendor-neutral option that publishes a normalized, machine-readable setup manifest under an open licence-free API. It is the integration target. Smithery is a candidate secondary metadata source if ranking quality proves insufficient.

### Manifest and Schema Stack

The registry's payload is `server.json`, currently at schema version **`2025-12-11`** (`https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json`). This schema is the entire reason a "connector" abstraction is buildable rather than hand-written per vendor — it already encodes "which fields must the user fill, and which of them are secret."

Top-level: `name` (reverse-DNS, e.g. `app.linear/linear`, `io.github.owner/server`), `title`, `description`, `version`, plus `packages[]` and/or `remotes[]`.

**`packages[]`** — required `registryType`, `identifier`, `transport`. Optional `version` (the schema **rejects ranges and the string `latest`**), `fileSha256` for integrity verification, `runtimeHint` (`npx`, `uvx`, `docker`, `dnx`), `runtimeArguments`, `packageArguments`, `environmentVariables`. `registryType` values include `npm`, `pypi`, `oci`, `nuget`, `mcpb`.

**`remotes[]`** — `RemoteTransport` objects extending streamable-HTTP or SSE transports, carrying `url`, `headers`, and `variables` for URL-template substitution.

**Input objects** (shared by headers, env vars, and arguments) carry exactly the metadata a generated form needs:

| Field | Meaning |
|---|---|
| `description` | User-facing help text |
| `format` | `string` (default), `number`, `boolean`, `filepath` |
| `isRequired` | Boolean, default `false` |
| `isSecret` | Boolean, default `false` — drives secure handling |
| `choices` | Array of allowed string values → renders as a select |
| `default` | Default value |
| `placeholder` | Example guidance |
| `value` | Value with `{curly_brace}` variable substitution |
| `variables` | Map backing that substitution |

`KeyValueInput` extends this with a required `name` (the header or env var name). `Argument` splits into `NamedArgument` (`type: "named"`, `name` as a dashed flag, `isRepeated`) and `PositionalArgument` (`type: "positional"`, `valueHint`, `isRepeated`).

_Assessment: this maps onto Aixle's existing storage with no new concepts — `KeyValueInput` on a remote → `mcp_servers.headers`; `environmentVariables` → `mcp_servers.env`; arguments → `mcp_servers.args`; `isSecret` → the existing masking path; `format`/`choices`/`isRequired` → generated form validation. The `fileSha256` and version-range prohibition are pre-existing supply-chain affordances we get for free._
_Confidence: High — read directly from the published JSON Schema._
_Source: https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json_

### Registry API Surface

Base URL `https://registry.modelcontextprotocol.io`. Current documented paths are **`/v0.1/*`**; the OpenAPI specification documents no `/v0/servers` path, although that legacy path still responds in practice (probed 2026-08-01). Any implementation should target `/v0.1`.

- `GET /v0.1/servers` — list servers
- `GET /v0.1/servers/{serverName}/versions` — all versions of a server
- `GET /v0.1/servers/{serverName}/versions/{version}` — a specific version; `latest` is a valid special value

`serverName` and `version` path segments **must be URL-encoded** (`io.modelcontextprotocol/everything` → `io.modelcontextprotocol%2Feverything`).

Query parameters on the list endpoint, verbatim from the OpenAPI spec:

| Param | Type | Notes |
|---|---|---|
| `search` | string | **"Search servers by name (substring match)"** |
| `limit` | integer | No maximum documented |
| `cursor` | string | Opaque; use `metadata.nextCursor` exactly |
| `updated_since` | RFC 3339 date-time | Forces `include_deleted` to `true` |
| `version` | string | `latest` or an exact version |
| `include_deleted` | boolean | Default `false` |

Response shape: `{ "servers": [...], "metadata": { "count": N, "nextCursor": "com.example/my-server:1.0.0" } }`.

**🔴 Load-bearing finding — `search` is name-substring only.** This was verified two ways: the OpenAPI description says "by name (substring match)", and a live probe of `?search=linear&limit=5` returned `app.linear/linear`, `io.github.Evozim/linear-broker`, `io.github.adelaidasofia/linear-mcp`, `io.github.pipeworx-io/linear`, `io.github.toolwright-adk/linear-bootstrap` — i.e. matches on the name string, with no evidence of description matching. A user typing "issue tracker", "bug tracking", or "CRM" will get **zero results** against a pure live-proxy implementation.

This directly contradicts the working assumption that discovery could be a thin live proxy in the style of `SkillsRegistryService`. Options and consequences are developed in the architecture step; the short version is that usable search requires holding a local copy and searching `name + title + description` ourselves — which is also precisely what the registry documentation tells aggregators to do.

_Confidence: High — OpenAPI text plus reproducible live probe._
_Sources: https://raw.githubusercontent.com/modelcontextprotocol/registry/main/docs/reference/api/openapi.yaml, https://registry.modelcontextprotocol.io/v0.1/servers?search=linear&limit=5_

**Status lifecycle.** Server metadata is "generally immutable, except for the `status` field," which may move to `deprecated` or `deleted`. `deleted` typically means a moderation-policy violation — "spam, malware, or illegal" — and the registry recommends aggregators drop those from their index. Consumers are told to keep their copy of `status` current. `_meta["io.modelcontextprotocol.registry/official"]` carries `status`, `isLatest`, `publishedAt`, `updatedAt`, `statusChangedAt`.
_Confidence: High — first-party documentation, confirmed in live payloads._

**Subregistry option.** An aggregator that also implements the registry's OpenAPI spec becomes a "subregistry," consumable by any MCP host through a standard interface, and may inject custom metadata under a reverse-DNS `_meta` key (the documented example carries `user_rating`, `download_count`, and `security_scan` results). Noted as a possible future product surface — Aixle could expose its own curated view to external clients — not a v1 requirement.
_Confidence: High._
_Source: https://modelcontextprotocol.io/registry/registry-aggregators_

### Packaging, Runtime, and Transport Targets

Two structurally different install targets come out of the manifest, and they have very different operational profiles for us:

**`remotes[]` — hosted HTTPS endpoints.** Nothing to run. We store a URL, optional headers, and (usually) delegate auth to OAuth. Aixle supports this end to end today: `MCPServer#auth_type = oauth`, `Mcp::OauthDiscoveryService` for dynamic client registration, per-user or shared credential scope, encrypted+masked header storage. Most first-party vendor connectors (Linear, Sentry, Notion, Atlassian and similar) ship this way.

**`packages[]` — a package to execute.** Requires a runtime: `runtimeHint` of `npx`, `uvx`, `docker`, or `dnx` across `npm`, `pypi`, `oci`, `nuget`, `mcpb` registries. Aixle already emits these as stdio entries: `base_adapter.rb:215` builds the env, `base_adapter.rb:242` the args, and `claude_code_adapter.rb:623-626` (plus the Cursor and Gemini adapters) writes `command`/`args`/`env` into the agent's MCP config. So `packages[]` support is largely *already implemented* — the catalog only has to fill the fields.

Two pre-existing facts strengthen the security position here:

- **Env is already scoped.** `mcp_stdio_env` merges `MCP_STDIO_BASE_ENV` (a single Playwright path var) with the server's own `env` — an MCP subprocess receives only its declared variables, not the agent container's environment. No credential bleed to fix.
- **Version pinning is already institutional knowledge.** `base_adapter.rb:232-253` pins `@playwright/mcp` to an exact version in the *emitted* command precisely because an unqualified spec let `npx` resolve a newer release (issue #340). The registry's own schema refuses version ranges and `latest`. Generalizing that pin to every catalog install is a small change to an established pattern, not a new mechanism.

_Confidence: High for the Aixle-side claims (read from source); High for the schema claims._

### Host-Side Stack (Aixle)

Rails backend with polymorphic project-scoped `MCPServer` (`kind` internal/custom, `transport` http/sse/stdio, `auth_type` none/static/oauth, `credential_scope` shared/per_user, jsonb `headers`/`env`/`args`), React + Mantine frontend with `zod4Resolver` forms and an existing `McpServerFormModal` + `ConfigItemValueField` for masked secret entry, and an established registry-integration precedent in `SkillsRegistryService` (live search, install-on-demand, provenance stored on the row as `package`/`source`, no local catalog table).

The `Skill` precedent is the natural template — but note the asymmetry that the search finding above exposes: **skills.sh offers real search, the MCP registry offers name-substring matching.** The precedent transfers structurally, not literally.

### Adoption and Threat Trends

MCP-specific supply-chain attacks moved from theory to documented practice during 2025–2026. OWASP codified tool poisoning as **MCP03:2025** in its MCP Top 10, grouping it with rug pulls and tool shadowing as attacks on the capability supply chain. By mid-2026 reporting describes multiple assigned CVEs and active threat intelligence around these patterns.

The three named variants:

- **Tool description poisoning** — hidden instructions inside a tool's description, which the model reads as part of its context.
- **Rug pull** — a benign tool is shipped and approved, then a malicious description is swapped in later.
- **Tool shadowing** — a malicious server's tool definitions override or impersonate a trusted server's.

The common structural cause identified in the research: **MCP clients inherit trust from the servers they connect to without continuous verification of that trust.**

Defences reported as effective: pinning exact versions with no caret ranges and committing lockfiles; maintaining an explicit allowlist of permitted servers by package name and version; and static analysis of manifests — Invariant Labs' `mcp-scan` checks tool descriptions and schemas for known poisoning patterns and **detects manifest changes between versions for rug-pull detection**.

_Design implication under our constraint #4 (no allowlist): of the three reported defences, we adopt exact-version pinning and manifest change-detection, and deliberately decline the allowlist. The change-detection leg is the important one — it is the direct counter to rug pulls, and it is cheap because `tools/list` verification is already planned at install time. Snapshot the tool set and descriptions at install, diff them at session start, surface a warning on drift._
_Confidence: High for the attack taxonomy (OWASP + multiple independent sources); Medium for the mid-2026 CVE-count claims (secondary reporting, not verified against CVE records in this pass)._
_Sources: https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks, https://techcommunity.microsoft.com/blog/microsoft-security-blog/the-state-of-mcp-security-in-2026/4531327, https://glasp.co/articles/mcp-security-tool-poisoning-supply-chain, https://labs.cloudsecurityalliance.org/research/csa-research-note-mcp-tool-poisoning-ai-agent-exfiltration-2/_

---

## Integration Patterns Analysis

### The Core Mapping: `server.json` → `MCPServer`

The central integration question is whether a registry manifest can be mechanically projected onto Aixle's existing storage. It can, with no schema invention:

| `server.json` element | Aixle destination | Notes |
|---|---|---|
| `remotes[].url` | `mcp_servers.url` | Direct |
| `remotes[].type` (`streamable-http` / `sse`) | `mcp_servers.transport` (`http` / `sse`) | Enum already exists |
| `remotes[].headers[]` (`KeyValueInput`) | `mcp_servers.headers` jsonb | `name` → key, user value → value |
| `remotes[].variables` | resolved at install into the stored `url` | `{curly_brace}` substitution |
| `packages[].runtimeHint` + `identifier` + `version` | `mcp_servers.command` | e.g. `npx -y @scope/pkg@1.2.3` |
| `packages[].runtimeArguments` / `packageArguments` | `mcp_servers.args` jsonb | Positional and named forms both flatten to argv |
| `packages[].environmentVariables[]` | `mcp_servers.env` jsonb | Already scoped per-server at emission |
| `isSecret: true` | existing encrypted + masked storage path | Reuses `ConfigItemValueField` masking sentinel |
| `isRequired` / `format` / `choices` / `default` / `placeholder` | generated Zod schema in the form modal | Direct analogues in the existing `zod4Resolver` setup |
| `name`, `version`, `_meta` status | provenance columns on the install row | Mirrors `Skill#package` / `Skill#source` |

_Assessment: the manifest is a superset of what the current manual form collects. Nothing in the schema requires a field Aixle cannot already store. The generated form is a rendering problem, not a data-model problem._
_Confidence: High — both sides read directly from source (JSON Schema; `db/schema.rb`, `McpServerFormModal.tsx`)._

### Transport Patterns and Their Deprecation State

Three transports appear in manifests, with sharply different trajectories:

- **Streamable HTTP** — the current standard remote transport. Introduced in protocol revision `2025-03-26`.
- **HTTP+SSE** — replaced by Streamable HTTP in `2025-03-26`, deprecated in prose since then, and as of the `2026-07-28` specification moved to formal Deprecated status under an actual deprecation policy (SEP-2596) with a twelve-month offramp. Aixle's `transport` enum still defaults to `sse` at the database level (`db/schema.rb`: `t.string "transport", default: "sse"`), while the model default is `http` — worth aligning, and worth defaulting catalog installs to `http` regardless.
- **stdio** — unaffected by the remote-transport churn; the dominant form for `packages[]`.

Clients are required to send `MCP-Protocol-Version` on requests after initialization, carrying the negotiated version.
_Confidence: High — multiple independent sources plus the first-party spec blog._
_Sources: https://blog.modelcontextprotocol.io/posts/2026-07-28/, https://blog.fka.dev/blog/2025-06-06-why-mcp-deprecated-sse-and-go-with-streamable-http/_

### Authorization Patterns

MCP's authorization model is now a conventional OAuth 2.1 arrangement: the MCP server is formally a **resource server** that validates access tokens and delegates authentication, consent, token issuance, and revocation to a separate authorization server. Servers **MUST** implement OAuth 2.0 Protected Resource Metadata (RFC 9728) so clients can discover the correct authorization server automatically.

**🔴 Consequential for Aixle: Dynamic Client Registration is deprecated as of `2026-07-28`.** The specification now prefers **OAuth Client ID Metadata Documents (CIMD)**. DCR "continues to work for backwards compatibility but is slated for removal in a future version." Additional hardening in the same release:

- RFC 9207 issuer validation — clients must validate the `iss` parameter before redeeming a code
- `application_type` is now set during DCR, fixing authorization servers that rejected `localhost` redirects for desktop and CLI clients
- Client credentials are bound to their issuing authorization server

Aixle's `Mcp::OauthDiscoveryService` is a DCR implementation. It is not broken — the deprecation window is explicitly backwards-compatible — but a catalog that dramatically increases the number of OAuth-backed connectors also increases exposure to whichever authorization servers drop DCR first. **Recommendation: treat CIMD support as a tracked follow-up with its own decision record, not as a blocker for the catalog.** It is orthogonal to the catalog work: the same connector installs either way, only the client-registration mechanism differs.

_Confidence: High — first-party specification blog, corroborated by two independent analyses._
_Sources: https://blog.modelcontextprotocol.io/posts/2026-07-28/, https://stacktr.ee/blog/mcp-2026-spec-changes, https://workos.com/blog/mcp-2026-spec-agent-authentication_

Aixle's existing `credential_scope` (`shared` vs `per_user`) has no counterpart in the registry manifest — the manifest describes *what a server needs*, not *who owns the credential*. This stays a local decision surfaced in the install form, defaulting to `shared` as today.

### Secret Handling Patterns

The manifest's `isSecret` flag is the interoperability point, and comparable systems converge on the same shape: Docker's MCP Toolkit runs a Secret Engine that stores PATs and OAuth tokens and injects them into containers at runtime, keeping them out of the manifest and out of image layers.

Aixle's equivalent already exists and is arguably stronger for the stdio case: `MCPServerResource` masks stored header/env values to a sentinel before they reach the browser, the controller swaps sentinels back for stored secrets on save, and `base_adapter.rb:215` (`mcp_stdio_env`) hands an MCP subprocess only its own declared variables merged with a single baseline path var — never the agent container's ambient environment.

_Design implication: a catalog install must write secret-flagged inputs through the same masked path as the manual form, and must never persist a secret into the provenance manifest snapshot. The snapshot stores the input **declarations**, not the input **values**._
_Confidence: High._
_Source: https://docs.docker.com/ai/mcp-catalog-and-toolkit/catalog/_

### Verification and Change-Detection Patterns

Under constraint #4 (no allowlist), install-time verification plus ongoing change-detection carries the security load. Three mechanisms are relevant, and they interact awkwardly:

**`tools/list` at install.** Confirms the connector actually works and yields the tool inventory to show the user. **But this makes Aixle itself an MCP client**, which it currently is not — the agent CLIs (Claude Code, Cursor, Gemini) are the MCP clients; Aixle only writes their config. Two consequences:

1. Server-side verification is realistically feasible only for **`remotes[]`**. Verifying a `packages[]` server would mean executing the package on our infrastructure, which constraint #3 rules out. For stdio installs, verification must either happen inside the agent container at session start, or be skipped with the UI saying so honestly.
2. Becoming an MCP client inherits protocol churn. The `2026-07-28` stateless core actually *reduces* this cost — the `initialize`/`initialized` handshake and `Mcp-Session-Id` are removed (SEP-2567, SEP-2575), with protocol version and capabilities travelling in `_meta` on every request — but servers on older revisions still expect a handshake, so a verifier needs both paths during the transition.

**`notifications/tools/list_changed`.** Servers declaring the `listChanged` capability SHOULD emit it when their tool set changes. This is the natural rug-pull tripwire — except that real-world client support is poor. Open issues in 2026 record Claude Code defining the Zod schema for the notification but registering no handler, and Claude desktop/mobile caching `tools/list` indefinitely so server-side schema updates never surface without a manual reconnect. Equivalent gaps are filed against OpenAI Codex.
_Implication: we cannot delegate rug-pull detection to the agent client. If we want it, we own it._

**`CacheableResult` (`2026-07-28`).** `tools/list`, `prompts/list`, `resources/list` (and `resources/read`) now carry `ttlMs` and `cacheScope` (`public` / `private`), borrowing HTTP `Cache-Control` semantics. This complements `listChanged` rather than replacing it, and exists precisely because stateless deployments can no longer vary list endpoints per connection.
_Implication: a periodic re-`tools/list` + diff against the install snapshot is now a spec-sanctioned pattern with server-provided freshness hints, rather than impolite polling._

_Confidence: High for the spec mechanics; High for the client-gap reports (tracked GitHub issues in the respective repositories)._
_Sources: https://github.com/anthropics/claude-code/issues/13646, https://github.com/anthropics/claude-code/issues/38324, https://github.com/openai/codex/issues/10105, https://stacktr.ee/blog/mcp-2026-spec-changes_

### Coexistence Pattern: Catalog Installs and Hand-Authored Servers

Constraint #5 requires the manual form to remain first-class. The clean pattern is **one table, optional provenance** rather than two parallel concepts:

- A hand-authored server has null provenance columns and behaves exactly as today.
- A catalog install carries `connector_name`, `connector_version`, and a manifest snapshot, which unlocks the extras: "update available" when the registry publishes a newer version, drift warnings, and a provenance badge.
- Everything downstream — `SessionConfigResolver`, the three agent adapters, `visible_for_project`, the policy — stays untouched, because both kinds are still just `MCPServer` rows.

This mirrors how `Skill` already works (`package`/`source` as provenance on an otherwise ordinary row) and avoids a second code path through session config generation, which is the part of the system where divergence would be most expensive.

An important corollary: a catalog install must remain **editable by hand afterwards**. Users will need to override a URL for a self-hosted instance of a catalogued product, or add a header the manifest does not declare. Provenance should therefore be advisory metadata, not a lock.
_Confidence: High — derived from the existing codebase structure._

### Prior Art in Client Tooling

Existing MCP clients expose install as flat configuration entry rather than manifest-driven forms: `claude mcp add --transport <stdio|http|sse> <name> <url-or-cmd>`, `claude mcp add-json`, VS Code's `.vscode/mcp.json` and `--add-mcp` flag. VS Code additionally supports input variables that prompt at resolution time.

_Assessment: there is no established, portable "install from registry with a generated form" UX to copy — the ecosystem is still at the level of hand-edited JSON, with Smithery's CLI and Docker's Toolkit as the main exceptions. This is a genuine product-differentiation opening for Aixle rather than a solved pattern to adopt. Confidence: Medium — absence of evidence from a single search pass is weaker than positive evidence._
_Sources: https://code.visualstudio.com/docs/agent-customization/mcp-servers, https://systemprompt.io/guides/claude-code-mcp-servers-extensions_

---

## Architectural Patterns and Design

### System Architecture Patterns — The Data Plane Decision

The open question from the technology-stack step is where catalog data lives. Three patterns are available; the choice is forced by the `search`-is-name-substring finding plus the registry's own operational disclaimers.

**Pattern A — Live proxy (thin).** Every catalog query hits `registry.modelcontextprotocol.io` synchronously. Mirrors `SkillsRegistryService` exactly; no new table.
_Fails on the primary use case._ Search is substring-on-name only, so "issue tracker", "CRM", "observability" return nothing. It also inherits an availability dependency the registry explicitly refuses to underwrite: "The MCP Registry **does not provide uptime or data durability guarantees**," with consumers told to "handle service downtime via caching." A catalog tab that is empty whenever a preview-status third-party service is down is not shippable.

**Pattern B — Local mirror (aggregator).** Scrape on a schedule, persist, search locally over `name + title + description`. This is the pattern the registry documentation prescribes: aggregators "are expected to scrape data on a regular but infrequent basis (e.g., once per hour), and persist the data in their own data store."
_Costs one table and a sync job; buys real search, offline resilience, our own ranking and curation, and per-row moderation status._

**Pattern C — Subregistry.** Pattern B plus implementing the registry's own OpenAPI spec so external MCP hosts can consume Aixle's curated view, injecting custom metadata under a reverse-DNS `_meta` key (the documented example carries `user_rating`, `download_count`, `security_scan`).
_Out of scope for v1, but worth noting as a product surface: it would make Aixle a discovery endpoint for other clients, not just a consumer._

**Scale check for Pattern B.** The official registry counted approximately **9,652 latest server records and 28,959 server/version records as of May 2026**, up from roughly 3,012 unique servers in March 2026. Third-party directories are larger (Glama ~22,775; mcp.so ~20,222) but heavily padded with forks and abandoned entries. Even extrapolating the March→May growth rate forward, the mirror is in the low tens of thousands of rows — trivially small for Postgres, and well within a single incremental sync.
_Confidence: Medium — counts come from secondary aggregated reporting, not a first-party statistics endpoint. Order of magnitude is what matters here, and multiple sources agree on it._
_Sources: https://www.digitalapplied.com/blog/mcp-ecosystem-h1-2026-retrospective-adoption-data-points, https://tooldirectory.ai/blog/state-of-mcp-servers-2026_

**Recommendation: Pattern B, with a live read at install time.** Browse and search serve from the mirror; the moment a user commits to installing, fetch that server's current manifest from `GET /v0.1/servers/{name}/versions/{version}` so the install is never built from stale mirror data. This is a hybrid that gets resilient discovery without risking a stale manifest becoming a stale — or silently wrong — installed configuration.

_This supersedes the earlier working assumption that no catalog table would be needed. The assumption was based on `SkillsRegistryService` precedent; it does not survive the discovery that the registry offers no description search and no availability guarantee._

### Design Principles and Best Practices

**Anti-corruption layer at the registry boundary.** The registry is explicitly in preview — "breaking changes or data resets may occur before general availability" — and has already moved `/v0` → `/v0.1` and its schema to `2025-12-11`. The frontend and the installer must never see raw `server.json`. A normalization step (registry dialect → our own `manifest` shape of `targets` / `inputs` / `auth` / `verify`) confines schema churn to one file and makes a second source (Smithery) additive rather than invasive.

**One table, optional provenance.** Established in the integration step, restated here as an architectural invariant: catalog installs and hand-authored servers are the same `MCPServer` row. No second code path reaches `SessionConfigResolver` or the three agent adapters.

**No foreign key from install to mirror.** The mirror is a *cache of someone else's data* and its rows legitimately disappear — a server can move to `deleted` status for moderation reasons, and the registry recommends aggregators drop those from their index. An install must survive its catalog entry vanishing. Store `connector_name` as a plain string plus a self-contained manifest snapshot; resolve to the mirror opportunistically for display. A real FK would either block moderation cleanup or cascade-delete working user configuration.

**The mirror is disposable.** The registry is the source of truth; our copy is rebuildable from zero by a full re-sync. This means it needs no backup story, no migration of its contents, and can be truncated and rebuilt if the registry does reset its data during preview.

**Snapshot declarations, never values.** The manifest snapshot on an install records what inputs *were declared* (names, `isSecret`, `isRequired`, `format`, `choices`). Actual user-supplied values live only in the existing encrypted `headers`/`env` columns. This keeps the snapshot safe to display, diff, and log.

### Scalability and Performance Patterns

**Incremental sync.** A full walk is `limit`-paginated by opaque cursor (`metadata.nextCursor`, passed back as `cursor`); at `limit=100` a ~10k-row catalog is ~100 requests. Steady state should instead use `updated_since` with an RFC 3339 timestamp, which returns only changed records — and note the documented side effect that **`updated_since` forces `include_deleted` to `true`**, which is exactly what a mirror wants, since it needs to learn about deletions. Cadence: hourly, per the registry's own guidance. No rate limits are documented, which is a reason to be conservative rather than aggressive.

**Search implementation.** Postgres over `name + title + description` on ~10–30k rows. Full-text search or trigram indexing both comfortably handle this volume; the choice is an implementation detail, not an architectural one. The important part is that it happens locally, because the upstream API cannot do it.

**Featured set resolution.** The pinned "popular connectors" list for the empty state is a code constant of server names resolved against the mirror — no network call on page load once the mirror exists, which removes the caching/stale-fallback complexity that a live-proxy featured list would have needed.

**Cost of verification.** `tools/list` at install is one network round trip per install for `remotes[]` connectors, and impossible server-side for `packages[]` (constraint #3). Periodic re-verification for drift detection should be driven by the `2026-07-28` `ttlMs` hint where present rather than a fixed interval.

### Integration and Communication Patterns

The sync job is a scheduled, idempotent, single-writer batch — the simplest possible shape. Aixle already runs both Solid Queue and Temporal schedules; the relevant prior lesson in this codebase is that Temporal schedule reconciliation has already caused a production incident (dynamic schedules wiped by a worker redeploy), so the sync should be placed on whichever mechanism the team currently treats as lowest-ceremony for a plain hourly cron, and must be safely re-runnable if it fires twice or is missed for a day. `updated_since` makes both cases harmless by construction.

### Security Architecture Patterns

The security posture is fully determined by constraint #4 (no allowlist) and must be documented as an *accepted risk with compensating controls*, not glossed over.

**Accepted risk.** Any server in a public, permissively-moderated registry can be installed into a project by any member with write access, and — for `packages[]` — will execute inside the agent container. The stated justification is that the agent container is already an arbitrary-code-execution environment.

**Compensating controls, in order of value:**

1. **Exact version pinning.** The schema itself refuses version ranges and `latest`. The emitted command must carry the resolved exact version, extending the pattern already established for `@playwright/mcp` (`base_adapter.rb:232-253`, issue #340). This is the single highest-value control, because it converts a rug-pull from silent to requiring an explicit user-visible update action. Independent security reporting names exactly this — "pin exact versions with `--save-exact` (no caret ranges)" — as a primary defence.
2. **Manifest and tool-set snapshot + diff.** Store the declared inputs and (where obtainable) the `tools/list` result at install; diff on update and periodically. This is the direct counter to rug pulls and tool-description poisoning, and per the integration-step finding it cannot be delegated to the agent clients, whose `listChanged` handling is demonstrably broken. Prior art exists: Invariant Labs' `mcp-scan` "detects manifest changes between versions (rug-pull detection)."
3. **Moderation status propagation.** Keep each mirrored server's `status` current, and handle the case of an *already-installed* server whose upstream entry flips to `deleted`, which "suggests the server might be spam, malware, or illegal."
   **✅ Decided (2026-08-01):** an installed connector whose registry entry is deleted **stays visible and stays running**, with a prominent warning on the project's MCP page and on the install row. No silent auto-disable — a false positive would break working projects without explanation, and the user is better served by an informed choice than by a surprise outage. Note the asymmetry this creates and implement it deliberately: deleted servers are **removed from catalog search results** (per the registry's recommendation to drop them from the index) while **remaining visible as installs**. The mirror therefore cannot hard-delete rows that any install still references by `connector_name`; it marks them and excludes them from discovery queries.
4. **Provenance display.** Namespace verification is meaningful and free: `io.github.*` names require GitHub OAuth (or GitHub Actions OIDC) by the owning user or org, and `com.example.*` names require DNS or HTTP proof of domain ownership. Surfacing "verified publisher" versus an anonymous namespace, alongside `_meta` status and `isLatest`, gives users the same judgement affordance the skills catalog already relies on.
5. **`fileSha256`.** Present in the package schema for integrity verification; worth capturing in the snapshot even before anything enforces it.

_Confidence: High for the mechanisms; the risk-acceptance is a product decision recorded here, not a research finding._
_Sources: https://glasp.co/articles/mcp-security-tool-poisoning-supply-chain, https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks, https://modelcontextprotocol.io/registry/authentication_

### Data Architecture Patterns

Two storage concerns, deliberately decoupled:

**Mirror table** (catalog): registry `name` as natural key, `version`, `title`, `description`, normalized `manifest` jsonb, `status`, `is_latest`, `updated_at` from upstream, plus room for locally-computed ranking. Global, read-only to users, rebuildable, no backup requirement.

**Provenance columns** on `mcp_servers`: `connector_name` (string, not FK), `connector_version`, `connector_manifest` (snapshot jsonb). Null for hand-authored rows. Nullable columns on an existing table rather than a join model, because the relationship is 1:1 and optional, and because every existing query path must keep working untouched.

This split means the catalog can be added, changed, or removed entirely without touching how sessions resolve their MCP configuration.

### Deployment and Operations Architecture

**Pin the API version explicitly to `/v0.1`.** The OpenAPI spec documents no `/v0` path, though it still responds; building against the undocumented legacy path would be a self-inflicted wound.

**Design for the registry being unavailable or reset.** Preview status admits both. Concretely: catalog browse degrades to the last successful mirror; install of a `remotes[]` connector can fall back to the mirrored manifest with a "could not confirm latest version" notice; and the manual form — constraint #5 — remains the always-available path, which is now not just a usability requirement but the operational fallback for the entire feature.

**Feature-flag the catalog tab.** The dependency is a third-party preview service; the ability to turn the surface off without a deploy is proportionate.

---

## Implementation Approaches and Technology Adoption

### Technology Adoption Strategy

The adoption pattern is **strictly additive, never migratory**. There is no legacy to modernize: the catalog adds an acquisition path alongside the manual form (constraint #5), and every existing `MCPServer` row keeps working with null provenance columns. This removes the usual big-bang-versus-gradual dilemma — there is nothing to cut over.

Two properties make the increment safe:

- **Nothing downstream changes.** `SessionConfigResolver`, `ContextBuilders::Tools`, and the three agent adapters see the same `MCPServer` rows as before.
- **The feature is failure-tolerant by construction.** If the mirror is empty, the registry is down, or the catalog is flag-disabled, the product degrades exactly to today's behaviour.

### Development Workflows and Tooling

**🟢 Material finding: the MCP client we need is already in the Gemfile.** `Gemfile:102` ships `gem "mcp"` — the official Ruby SDK, maintained in collaboration with Shopify — currently resolved to **1.0.0** in this project. It is presently used only for the *server* side (`MCP::Server` built per request in `McpController` / `Tools::McpRequestHandler`), but the installed gem also carries a full client:

- `MCP::Client` with `#connect`, `#list_tools(cursor:)`, `#tools`, `#ping`, `#call_tool`
- `MCP::Client::HTTP` transport (with an `InsecureURLError` guard and SSE stream handling)
- `MCP::Client::OAuth` with `discovery.rb`, `pkce.rb`, `provider.rb`, `storage_backed_provider.rb`, `client_credentials_provider.rb`, `jwt_client_assertion.rb`, `cross_app_access_provider.rb`

_This revises the step-3 cost estimate downward. Install-time `tools/list` verification for `remotes[]` connectors is not a "build an MCP client" project; it is wiring an existing, already-vendored client. The same OAuth provider stack is also the natural place to look when the CIMD follow-up is picked up._
_Confidence: High — read from the gem installed in this project's bundle, not from documentation._
_Sources: `Gemfile:102`, `bundle show mcp` (1.0.0), https://ruby.sdk.modelcontextprotocol.io/_

The rest of the stack is entirely familiar: a Rails service for registry access mirroring `SkillsRegistryService`'s shape, a Solid Queue or Temporal-scheduled sync job, an Inertia page with a Mantine modal, and `zod4Resolver` for the generated form (never bare `zodResolver` — zod 4 is what is installed).

### Testing and Quality Assurance

`docs/testing.md` governs, and it constrains the design in ways worth naming up front:

- **R2 — don't mock what you don't own.** The `mcp` gem must not be stubbed in tests. Verification has to sit behind an app-owned adapter (e.g. `Mcp::ToolListProbe`) so tests stub *ours*. The same applies to the registry HTTP client: an app-owned adapter, not raw `Net::HTTP` expectations. `Testing/NoVendorStubbing` enforces this in rubocop.
- **R3/R4 — one canonical fake per boundary, contract-tested.** The registry adapter gets WebMock `stub_request` contract tests with realistic `server.json` payloads (the `2025-12-11` shape, including a `packages[]`-with-`environmentVariables` case and a `remotes[]`-with-secret-headers case), plus one canonical fake in `test/support/fakes/` used by everything upstream. `test/services/skills_registry_service_test.rb` is the existing precedent to follow.
- **Layer assignment.** Normalization (registry dialect → our manifest) is pure logic and belongs in unit tests with fixture payloads — this is where schema-churn regressions will actually be caught. The installer is a service test on the real DB asserting the resulting `MCPServer` row. The catalog controller gets an `ActionDispatch::IntegrationTest` with `assert_inertia_props`. No new policy class means no new policy matrix, but `test/support/authorization_matrix.rb` needs the new routes added.
- **Frontend.** The generated form is a component test (Vitest + RTL, role/label queries, `userEvent`) driven by manifest fixtures — every input `format`, plus `isRequired`, `choices`, and the secret-masking path. No snapshots, no `querySelector`.
- **Coverage floors are ratchets** (`COVERAGE_MIN` in the `Makefile`, `coverage.thresholds` in `vitest.config.ts`) — a feature of this size must raise them, never lower them.
- **Before pushing:** `docker compose exec -T web make check_all`, and `docs/index.md` updated in the same change as any new doc under `docs/`.

A note specific to this feature: **fixture payloads are the test asset that matters most.** The upstream schema is in preview and will move. Capturing real `server.json` responses as fixtures — one per shape, refreshed deliberately — is what turns an upstream breaking change from a production incident into a red test.

### Deployment and Operations Practices

- **Sync job:** hourly, idempotent, single-writer, driven by `updated_since`. Safe on double-fire and on multi-day gaps by construction. Given this codebase's prior incident with Temporal schedule reconciliation wiping dynamic schedules on worker redeploy, prefer whichever scheduler the team currently treats as lowest-ceremony for a plain hourly cron, and make the job's own recovery independent of the schedule surviving.
- **Feature flag** on the catalog surface; the dependency is a third-party preview service.
- **Observability:** sync duration, rows upserted, upstream error rate, and — the one that actually matters operationally — **time since last successful sync**, since a silently stale mirror is the failure mode users would notice last and complain about first.
- **Backfill/rebuild:** a full re-sync must be runnable on demand, because the registry may reset data during preview.

### Team Organization and Skills

No new technology is introduced: Rails services, Postgres, a scheduled job, Inertia/React/Mantine, and a gem already in the bundle. The genuinely new *knowledge* is MCP protocol semantics (transports, the `2026-07-28` stateless core, OAuth resource-server model) — concentrated in the verification component, which is also the most deferrable piece. This makes the phasing below staffable by whoever normally works this codebase, with the protocol-heavy work isolated to a late phase.

### Cost Optimization and Resource Management

The mirror is the cheap part: tens of thousands of small rows, hourly incremental updates, no backup requirement, disposable. The expensive part is **frontend work on the generated form** — rendering arbitrary declared inputs with per-format validation, secret masking, and a coherent OAuth handoff. Budget accordingly; the temptation to under-invest here produces a catalog that installs connectors users then have to fix by hand, which is worse than no catalog.

### Risk Assessment and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Registry breaking change / data reset during preview | High — self-declared | Medium | Anti-corruption normalization layer; fixture-based contract tests; disposable rebuildable mirror; pinned `/v0.1` |
| Malicious or hijacked package installed (no allowlist) | Medium | High | Exact version pinning; manifest + tool-set snapshot and diff; provenance/verified-namespace display; moderation-status warnings |
| Rug pull after approval | Medium | High | Snapshot + periodic re-`tools/list` diff — cannot be delegated to agent clients, whose `listChanged` handling is broken |
| DCR removed by an authorization server | Low near-term | Medium | Deprecation window is open and explicitly backwards-compatible; CIMD tracked as a separate follow-up |
| Stale mirror silently serving old manifests | Medium | Medium | Live manifest fetch at install time; "time since last successful sync" alerting |
| Generated form fails to express an exotic manifest | Medium | Low | Manual form remains first-class; catalog installs stay hand-editable afterwards |
| Verification impossible for `packages[]` | Certain | Low | Accepted and disclosed in UI; do not imply a check that did not happen |

_The last row is the one most likely to be quietly violated in implementation: a green "verified" badge on a stdio install that was never actually probed would be a lie the whole security story rests on._

## Technical Research Recommendations

### Implementation Roadmap

**Phase 1 — Catalog + `remotes[]` installs.** Mirror table, hourly sync, local search over `name + title + description`, catalog browse with a code-pinned featured set, generated install form, install → `MCPServer` with provenance, handoff to the existing OAuth/DCR flow. Highest value per unit of risk: no new code execution, and most first-party vendor connectors are remote.

**Phase 2 — `packages[]` / stdio installs.** Emit `command`/`args`/`env` with the exact version pinned, disclose "runs code in your agent container" in the UI. Small: the adapters already emit stdio config; this is filling fields.

**Phase 3 — Verification and drift detection.** App-owned probe over `MCP::Client` for remotes at install; snapshot tools and descriptions; periodic diff honouring `ttlMs`; warnings for drift and for upstream `deleted` status (per the 2026-08-01 decision: warn, keep running, hide from search).

**Phase 4 — Update path.** Surface "newer version available" from the mirror; bumping the pinned version is an explicit user action showing the manifest/tool diff.

**Parked, with reasons:** CIMD migration (deprecation window open, orthogonal); subregistry mode (product surface, not user need); Smithery as a second metadata source (only if ranking quality proves insufficient); company-scope connectors (constraint #1).

### Technology Stack Recommendations

Official MCP Registry `/v0.1` as the single upstream. Postgres mirror with local text search. `mcp` gem 1.0.0 client behind an app-owned adapter for verification. Existing OAuth/DCR machinery unchanged. Existing `MCPServer` table with three added nullable provenance columns; no join model, no foreign key to the mirror.

### Skill Development Requirements

One area only: MCP protocol semantics for whoever builds Phase 3 — transports and their deprecation state, the `2026-07-28` stateless core, and the OAuth resource-server model. Phases 1–2 need no new expertise.

### Success Metrics and KPIs

- **Adoption:** share of new MCP servers created via catalog versus manual form. The manual form retaining meaningful usage is a healthy signal, not a failure — it means private and self-hosted endpoints are being served.
- **Install success rate:** installs that reach a working state without subsequent manual edits. This is the direct measure of whether the generated form is doing its job.
- **Time-to-first-working-connector** for a new project, versus the manual baseline.
- **Mirror freshness:** time since last successful sync (operational SLI).
- **Security posture:** number of installs on a pinned exact version (target 100% of catalog installs), and drift warnings raised versus acted upon.

---

## Future Technical Outlook

**Near term (next 6–12 months).** Three dated trajectories bear directly on this feature:

- **Registry general availability.** The Official MCP Registry launched in preview on 8 September 2025 and remains in preview, with GA "to follow later" and no published date. Reporting on the 2026 roadmap describes a Q4 milestone for "a curated, verified server directory with security audits, usage statistics, and SLA commitments." If that lands as described, two of the compensating controls designed here — provenance display and moderation-status propagation — get stronger upstream inputs, and the mirror's ranking problem gets easier. Aixle should not wait for it; the mirror design is unaffected either way.
  _Confidence: Medium — GA intent is first-party, the Q4 curated-directory detail is secondary reporting with no first-party date._
- **DCR removal.** Deprecated in `2026-07-28`, "slated for removal in a future version," with no removal date announced. The practical risk is not the spec but individual authorization servers moving early. Watching for the first DCR rejection in production is a cheaper trigger than a speculative migration.
- **HTTP+SSE removal.** Formally deprecated with a stated twelve-month offramp (SEP-2596), putting removal around mid-2027. Catalog installs should default to `http`; the database-level `transport` default of `sse` is a latent inconsistency worth correcting independently of this feature.

**Medium term.** The `2026-07-28` release is described as the largest revision since launch — a stateless core, an extensions framework, MCP Apps (server-rendered UIs), and a Tasks extension for long-running work. Two of these could reshape what a "connector" means in the product: server-rendered UI would let a connector contribute interface rather than only tools, and the Tasks extension intersects with how workflow steps model long-running operations. Both are out of scope here and neither blocks the catalog, but a connector abstraction designed now should not assume tools are the only thing a server contributes.

**Innovation opportunity.** The absence of manifest-driven install UX across major clients is the clearest opening surfaced by this research. The subregistry pattern compounds it: Aixle could publish its curated, security-scanned view through the registry's own OpenAPI spec, injecting ratings and scan results under a reverse-DNS `_meta` key, making it a discovery endpoint other MCP hosts consume rather than only a consumer. Recorded as an opportunity, deliberately parked.

_Sources: https://blog.modelcontextprotocol.io/posts/2026-mcp-roadmap/, https://blog.modelcontextprotocol.io/posts/2026-07-28/, https://modelcontextprotocol.io/registry/registry-aggregators_

---

## Research Methodology and Source Verification

### Approach

Documentation review combined with **live API probing** — several load-bearing conclusions could not have been reached from documentation alone, and two contradicted it. Codebase claims were read directly from source in this repository and from the installed gem in the project's bundle, never inferred.

Specifically verified by probe rather than prose:

- `search` semantics — `GET /v0.1/servers?search=linear&limit=5` returned only name-matching servers, corroborating the OpenAPI description and disqualifying the live-proxy design.
- `/v0` versus `/v0.1` — the legacy path still responds despite being absent from the OpenAPI specification.
- `mcp` gem capability — `bundle show mcp` (1.0.0) plus direct inspection of `lib/mcp/client/`, which revealed a client and OAuth stack that documentation searches had not surfaced.
- Aixle's stdio emission and env scoping — read from `base_adapter.rb` and the three adapter implementations.

### Primary Sources (first-party)

| Source | Used for |
|---|---|
| https://modelcontextprotocol.io/registry/registry-aggregators | Aggregator guidance, scrape cadence, uptime disclaimer, pagination, `updated_since`, status lifecycle, subregistry pattern |
| https://raw.githubusercontent.com/modelcontextprotocol/registry/main/docs/reference/api/openapi.yaml | Exact query parameters; `search` = name substring |
| https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json | Full `packages[]` / `remotes[]` / input object schema |
| https://blog.modelcontextprotocol.io/posts/2026-07-28/ | Stateless core, DCR deprecation → CIMD, header routing, `CacheableResult` |
| https://blog.modelcontextprotocol.io/posts/2026-mcp-roadmap/ | 2026 roadmap and registry trajectory |
| https://modelcontextprotocol.io/registry/authentication | Namespace verification (GitHub OAuth/OIDC, DNS, HTTP) |
| https://registry.modelcontextprotocol.io/v0.1/servers | Live probes |
| https://docs.docker.com/ai/mcp-catalog-and-toolkit/catalog/ | Docker curation and Secret Engine model |
| https://smithery.ai/docs/build/deployments/typescript | Smithery `configSchema` |
| https://code.visualstudio.com/docs/agent-customization/mcp-servers | VS Code install UX |
| https://ruby.sdk.modelcontextprotocol.io/ | Ruby SDK positioning |
| GitHub issues: anthropics/claude-code [#13646](https://github.com/anthropics/claude-code/issues/13646), [#38324](https://github.com/anthropics/claude-code/issues/38324); openai/codex [#10105](https://github.com/openai/codex/issues/10105) | Broken `listChanged` handling in shipping clients |

### Secondary Sources

Registry scale figures ([digitalapplied.com H1 2026 retrospective](https://www.digitalapplied.com/blog/mcp-ecosystem-h1-2026-retrospective-adoption-data-points), [tooldirectory.ai](https://tooldirectory.ai/blog/state-of-mcp-servers-2026)); MCP security landscape ([Microsoft Community Hub](https://techcommunity.microsoft.com/blog/microsoft-security-blog/the-state-of-mcp-security-in-2026/4531327), [Glasp](https://glasp.co/articles/mcp-security-tool-poisoning-supply-chain), [CSA Labs](https://labs.cloudsecurityalliance.org/research/csa-research-note-mcp-tool-poisoning-ai-agent-exfiltration-2/), [Invariant Labs](https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks)); spec-change analysis ([Stacktree](https://stacktr.ee/blog/mcp-2026-spec-changes), [WorkOS](https://workos.com/blog/mcp-2026-spec-agent-authentication)); transport history ([fka.dev](https://blog.fka.dev/blog/2025-06-06-why-mcp-deprecated-sse-and-go-with-streamable-http/)); Smithery review ([clawnewbie](https://clawnewbie.com/tools/smithery)); AWS Quick Suite connections ([AWS](https://aws.amazon.com/quicksuite/connections/), [docs](https://docs.aws.amazon.com/quick/latest/userguide/mcp-integration.html), [VPC MCP announcement](https://aws.amazon.com/about-aws/whats-new/2026/06/amazon-quick-vpc-mcp/)).

### In-Repository Sources

`Gemfile:102`; `bundle show mcp` → 1.0.0 with `lib/mcp/client/{http,oauth}`; `app/models/mcp_server.rb`; `app/models/skill.rb`; `app/services/skills_registry_service.rb`; `app/services/agents/base_adapter.rb:205-253`; `app/services/agents/claude_code_adapter.rb:617-626`; `app/services/session_config_resolver.rb`; `app/policies/web/company/projects/mcp_servers_policy.rb`; `app/frontend/shared/resources/mcp-servers/McpServerFormModal.tsx`; `db/schema.rb`; `docs/testing.md`.

### Confidence Levels and Limitations

**High confidence:** everything read from the JSON Schema, the OpenAPI specification, first-party spec and registry documentation, live API probes, and this repository's source and bundle.

**Medium confidence:** registry population figures (secondary aggregation, no first-party statistics endpoint — the order of magnitude is what the design depends on, and sources agree on it); the claim that no major client offers manifest-driven install UX (absence of evidence from a bounded search); mid-2026 CVE-count assertions in security reporting (not verified against CVE records); the Q4 curated-directory roadmap detail.

**Known limitations:**

- No hands-on prototype was built; the `server.json` → `MCPServer` mapping is verified against both schemas but not exercised end-to-end against a real install.
- Smithery's API was reviewed through documentation and reviews only, not probed. If it is ever promoted from parked to a second source, its API deserves the same live verification the official registry received here.
- Registry rate limits are undocumented; sync cadence is therefore set conservatively by the registry's own "once per hour" guidance rather than by measured headroom.
- The mirror's ranking and relevance design is deliberately left open — it is a product-quality question best answered with real query logs rather than by research.

---

## Addendum: Corrections From Implementation (2026-08-01)

The mapping prototype recommended in "Next Steps" was built the same day (`MCP::ConnectorManifest`,
`MCP::ConnectorAttributes`, six real payloads captured as fixtures in
`test/fixtures/files/mcp_registry/`). Driving live data through it **falsified four claims made
above from documentation alone**. The research body is left as written; these corrections take
precedence over it.

1. **`_meta` is a sibling of `server`, not a key inside it.** A registry entry is
   `{"server": {...}, "_meta": {...}}` — for both the list endpoint and the single-version
   endpoint (verified identical). The body of this document describes `_meta` as if it lived on
   the server object.
2. **The registry serves mixed schema versions simultaneously.** A single list response contained
   both `2025-09-29` and `2025-12-11` payloads. The anti-corruption layer is therefore not
   defensive design for a hypothetical future change — it is required today.
3. **`packages[].transport.type` is not always `stdio`.** Real npm packages ship
   `streamable-http` and `sse` transports with a *local* url template
   (`http://127.0.0.1:{port}/mcp`): the process is launched locally and then spoken to over HTTP.
   The claim above that `packages[]` implies stdio, and the phase split that followed from it, are
   wrong in this detail — a package install can produce an http-transport row that also has a
   command.
4. **`version: "latest"` occurs in production payloads**, despite the published schema stating
   that exact versions are required and ranges/`latest` are rejected. This directly undermines the
   assumption that exact-version pinning comes free from the schema. The normalizer surfaces
   `version_pinned: false` and the mapper refuses to fabricate a pin. **Resolved (decision 12):**
   such targets install anyway — consistent with the no-allowlist stance — with the missing pin
   made visible rather than silently accepted.
5. **Package targets are not all installable.** A package whose transport is `streamable-http` or
   `sse` must be launched locally *and* connected to over loopback, which agent MCP config cannot
   express: the adapters emit `command`/`args`/`env` for stdio entries and `url`/`headers` for
   everything else, never both. Installing one would write a config pointing at a port where
   nothing is listening — and the loopback url is independently rejected by `UrlSafetyValidator`.
   These targets are surfaced with an `unsupported_reason` so the UI can explain the refusal
   (decision 13). This narrows finding 3 above: reading the transport matters precisely *because*
   most non-stdio package targets have to be declined.

Also observed but not load-bearing: `packages[]` carries a `registryBaseUrl` field absent from the
schema summary; `repository` may be an empty object; `title` is frequently absent.

**Design decision taken during implementation.** Declared input defaults are **not** written
silently into a saved config. A default is a form suggestion; persisting one records a choice the
user never made and would override the package's own default if it later changed.
`ConnectorManifest.default_values(target)` exposes them for explicit pre-filling by the form or any
non-interactive caller.

**Confirmed as designed:** the `server.json` → `MCPServer` projection needs no new concepts. Real
Linear, filesystem and multi-package payloads persist as valid `MCPServer` rows through the
ordinary model path, provenance stays null for hand-authored rows, and a catalog install remains
editable afterwards. 40 tests, `make check_all` green.

---

## Appendix: Decision Log

Decisions taken during this research, with rationale, so the spec that follows does not relitigate them:

| # | Decision | Rationale | Date |
|---|---|---|---|
| 1 | Catalog metadata global; installs project-scoped only | Matches the current `MCPServer` model; no company-scope demand | 2026-08-01 |
| 2 | Any project member with write access may install | `MCPServersPolicy#create? = project_writable?` already expresses this; no new policy | 2026-08-01 |
| 3 | Aixle does not host MCP servers | Agent containers already launch node/python processes; a separate hosting tier is unjustified cost | 2026-08-01 |
| 4 | No allowlist — the whole registry is installable | Agent container is already an arbitrary-code-execution environment; partial gating is theatre. Burden shifts to version pinning + drift detection | 2026-08-01 |
| 5 | Manual entry stays first-class | Private/self-hosted endpoints and unlisted servers must remain addable; also the operational fallback when the registry is unavailable | 2026-08-01 |
| 6 | No seed files; discovery via API, featured set pinned in code | Registry is the source of truth; a seed list would rot | 2026-08-01 |
| 7 | Third-party hosting (Smithery runtime) rejected | Customer credentials would transit a third party; not topology-neutral for OSS self-hosting | 2026-08-01 |
| 8 | Local mirror over live proxy | Registry `search` is name-substring only; registry disclaims uptime and prescribes mirroring | 2026-08-01 |
| 9 | Installed connectors deleted upstream stay visible and running, with a warning; hidden from catalog search | False positives would silently break working projects; the user is better served by an informed choice | 2026-08-01 |
| 10 | No foreign key from installs to the mirror | Mirrored rows legitimately disappear under moderation; an install must outlive its catalog entry | 2026-08-01 |
| 11 | CIMD migration parked as a tracked follow-up | Deprecation window is open and explicitly backwards-compatible; orthogonal to the catalog | 2026-08-01 |
| 12 | Unpinnable packages (`version: "latest"`) are installable, not refused | Consistent with #4 — the catalog does not gatekeep. The missing pin is surfaced instead (`MCPServer#connector_version_pinned?`) so the UI can warn and drift detection can prioritise those installs | 2026-08-01 |
| 13 | Package targets whose transport is not stdio are marked unsupported | Such a target means "launch locally, then speak HTTP to it on loopback", and agent MCP config cannot express both — adapters emit command/args/env for stdio and url/headers otherwise, never both. Installing one would point the agent at a port where nothing listens. The loopback url is also correctly rejected by `UrlSafetyValidator` | 2026-08-01 |
| 14 | Declared input defaults are never written silently | A default is a form suggestion; persisting one records a choice nobody made and would override the package's own default if it changed. `ConnectorManifest.default_values` exposes them for explicit pre-fill | 2026-08-01 |
| 21 | The registry has NO popularity signal; the featured seed is built from two evidence sources, measured once | Verified directly: the registry publishes no installs, downloads or ratings. The seed therefore combines (a) **vendor-verified** namespaces — a registrable domain, granted only after a DNS/HTTP ownership challenge, so a customer subdomain cannot pose as the vendor; these are hosted services with no repo to measure — and (b) **measured** GitHub stars from a ONE-OFF pass over 9,377 publisher-owned repositories (8,000 answered; 1,206 registry entries point at repositories that no longer exist), deduplicated by repository so a monorepo shipping four servers cannot take four slots. Caveat carried in the code: stars belong to a REPOSITORY, so for a server inside a large product repo they measure the product. No recurring star-fetching code ships — a scheduled version was prototyped and removed as out of scope. `install_count` outranks the whole seed as soon as the platform has one | 2026-08-01 |
| 22 | Bulk publishers are demoted, never hidden | The open registry carries namespaces with 100–300 generated entries beside vendors shipping one. Namespace volume separates them with no maintained blocklist (~2.7k of 19.5k mirrored). Ranking only — everything stays searchable and installable, per decision 4 | 2026-08-01 |
| 23 | Auth requirement is detected by probing, not inferred from the manifest | A `server.json` declares INPUTS, never an auth model, so a hosted connector arrives looking exactly like a public one — Linear installed as `auth_type: none` until the install began asking. An MCP server that needs a token answers 401; the installer reads that, and the drift sweep applies the same rule to rows created before the check existed | 2026-08-01 |
| 19 | Catalog sync runs weekly, not the hourly cadence the registry suggests | Only DISCOVERY goes stale — an install re-fetches its manifest live, so a week-old mirror cannot produce a week-old configuration. The cost is a newly published connector taking up to a week to become searchable, against a service that publishes no rate limits and disclaims its own uptime | 2026-08-01 |
| 20 | "Popular" means this platform's own install count, used for ordering only and never displayed | The Official MCP Registry publishes no popularity signal at all — no installs, downloads or ratings — so any other figure would be invented. The count is not shown because an exact figure aggregated across every company is tenant usage data. A curated `FEATURED` list breaks the tie while every count is zero, and it is a display hint, not an allowlist | 2026-08-01 |
| 24 | Normalization is versioned; a bump forces a full re-walk | `MCP::ConnectorManifest`'s output is PERSISTED, which makes it a schema: changing it leaves every mirrored row describing the world under the old rules, and an incremental sync never revisits entries the registry left alone. It bit once — marking SSE uninstallable had no visible effect. `ConnectorManifest::VERSION` + a `normalizer_version` column let the sync detect and repair it | 2026-08-01 |
| 25 | Runtimes are resolved against the agent image, not the publisher's hint | A manifest names the runtime ITS publisher used. The image ships npx, uvx (added for this) and pipx — no Docker, no .NET. Emitting a hint verbatim produced `uvx` before uv existed in the image: installs looked clean and failed at session start. OCI and NuGet packages are refused with the specific reason. A test reads `docker/base/Dockerfile` and fails if the catalog offers a runtime the image lacks, because the promise and the image live in different files | 2026-08-01 |
| 26 | SSE targets are never installable, even as a connector's only remote | Deprecated upstream (SEP-2596) and — decisively — unverifiable here: the transport opens with a GET stream advertising a separate message endpoint, so the direct POST every probe makes answers 404. An SSE install would never get a tool baseline, never have its auth requirement detected, and never be drift-checked, while looking exactly like one that had. 413 of ~19.5k connectors are SSE-only; those stay addable by hand | 2026-08-01 |
| 27 | A failed page aborts the walk loudly instead of ending it quietly | The client treated a network failure as "no more pages", so a sync truncated at 200 servers reported success — indistinguishable from a genuinely small registry. Now `WalkInterrupted`, surfaced on the result. This immediately exposed the real cause: a 15s read timeout against a registry whose tail latency is higher, now 45s with three attempts per page | 2026-08-01 |
| 16 | Verification probes remote servers only; stdio installs are never probed | Probing a package means executing it, and packages run in the agent container, not here (decision 3). The UI says "not checked" rather than implying a check happened — a green badge on an unprobed install would undermine the whole no-allowlist rationale | 2026-08-01 |
| 17 | The drift sweep never moves the baseline; only a person accepts a change | If a re-probe silently became the new baseline, a rug pull would be recorded once and normalised away on the next run. `ToolDriftDetector.check` records drift and leaves the snapshot; `accept` is a separate route and an explicit act | 2026-08-01 |
| 18 | Tool declarations are stored as digests, not text | The snapshot only has to answer "did this change?". Keeping a copy of attacker-controlled descriptions invites rendering them somewhere later — and the description is precisely the payload in a tool-poisoning attack | 2026-08-01 |
| 15 | The catalog lives on the MCP servers page — no separate screen or nav entry | A connector is not a resource of its own: it is a pre-described way to create an `MCPServer`. Browsing is served with that page (`connectors` prop, gated by `MCPServersPolicy`), and `ConnectorsController` exposes only `create`. Presenting it as its own section would imply two kinds of thing where there is one, and would need a second permission surface for the same capability | 2026-08-01 |

---

## Conclusion and Next Steps

The feature is smaller than it looks, and the reason is that most of it already exists. Aixle has the runtime, the credential handling, the stdio plumbing, an MCP client sitting unused in its own bundle, and a proven registry-integration pattern in the skills feature. What the Official MCP Registry adds is the one missing piece: a declared, machine-readable statement of what each connector needs from the user. The gap between "paste raw transport config" and "fill in three labelled fields" is closed by data that already exists and is free to consume.

Two research findings changed the design rather than confirming it, and both are worth carrying forward as cautions about the upstream dependency: search is far weaker than the API surface suggests, and the authorization mechanism Aixle depends on was deprecated four days before this document was written. Neither is fatal, both were invisible from documentation summaries alone, and both argue for the same posture — treat the registry as an untrusted, fast-moving upstream behind a normalization layer, and keep the manual path alive so the product never depends on a preview service being healthy.

The security decision to allow everything is defensible on its stated grounds, but it is only defensible if the compensating controls are actually built. Exact-version pinning and install-time snapshotting are not polish to be deferred out of Phase 3 — they are the entire argument for why an open catalog is acceptable. Shipping the catalog without them would convert a reasoned risk acceptance into an unexamined one.

**Next steps:**

1. **Write the spec** (`docs/specs/`) from this research, carrying the decision log forward as frozen intent so those eleven decisions are not reopened during implementation.
2. **Prototype the mapping first.** Take three real `server.json` payloads — one remote-with-OAuth, one remote-with-secret-header, one npm package with environment variables — and drive them through normalization into `MCPServer` rows in a test. This is the cheapest possible falsification of the central claim, and it doubles as the contract-test fixture set.
3. **Open the CIMD follow-up** as its own tracked item, referencing `Mcp::OauthDiscoveryService` and the `mcp` gem's OAuth provider stack as the likely implementation surface.
4. **Fix the incidental finding** — the `mcp_servers.transport` database default of `sse` disagrees with the model default of `http`, and SSE is now formally deprecated upstream.

---

**Technical Research Completion Date:** 2026-08-01
**Source Verification:** All external claims cited; load-bearing claims verified by live probe or first-party specification; in-repository claims read from source
**Technical Confidence Level:** High for design-determining findings; Medium where explicitly annotated
