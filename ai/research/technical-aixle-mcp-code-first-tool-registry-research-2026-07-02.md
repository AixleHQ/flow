---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Aixle MCP code-first tool registry (DB-less platform tools, tagging, availability gating)'
research_goals: 'Design a registry where code-defined platform tools are available without DB rows; DB stays the store for user-created custom tools only. Add a clean tagging/categorization system for code tools (current kinds: custom/system/internal/workflow/meta are muddled). Add a per-tool availability predicate to hide tools when their integration is absent in the project/session (e.g. slack_post_message without Slack, coder_* without Coder). Define a safe migration path from the current DB-seeded scheme (seeds + idempotent data migrations), accounting for FK references (tool_results.tool_id, session_tools).'
user_name: 'Artem_Petrov'
date: '2026-07-02'
web_research_enabled: true
source_verification: true
---

# Code-First Tool Registry for the Aixle MCP Server: Technical Research

**Date:** 2026-07-02
**Author:** Artem_Petrov
**Research Type:** technical

---

## Executive Summary

Aixle's MCP tool system today keeps every tool — including ~50 platform tools whose behavior lives in code — as hand-seeded DB rows, coupled to their `InternalTools::*` handlers only by a naming convention, categorized by a five-value `kind` enum with semantics scattered across scopes and controllers, and gated by three divergent integration-check mechanisms. This research designed a replacement: a **code-first registry** where writing a handler class *is* the registration, the DB stores only user-created docker-image tools, tags replace `kind`, and one `available?(context)` predicate gates tools by integration presence everywhere.

**Key technical findings:**

- The ecosystem consensus (Dify, OpenHands, LibreChat; Solid Queue, Flipper, maintenance_tasks in Rails) is exactly the target split: schema + handler + metadata + availability co-located in code; DB rows only for tenant state or user-authored definitions; string keys or machine-owned mirror rows — never hand-maintained rows — bridging FKs.
- Per-request computation of `tools/list` from the authenticated session is the only mechanism that works across all MCP clients (`list_changed` push is unreliable ecosystem-wide) and is explicitly blessed by the upcoming 2026-07-28 MCP revision. Aixle's TerminalSession-per-request model is already aligned.
- The actionmcp gem (pinned 0.104.1, latest 0.111.1) still has no extension point for DB-backed tools — the monkey-patch stays for now — and its native registry is non-thread-safe and dev-reload-wiped, so the new registry deliberately avoids it. The endorsed long-term exit is the official `mcp` gem's server-per-request idiom.
- A three-architect design panel judged by three lenses chose **minimal-churn evolution** (Solid Queue-style shadow rows keeping every FK intact) over both a clean-slate rewrite and a security-maximalist design — then grafted the security design's structural anti-shadowing (resolution order, `mcp__%` CHECK constraint, provenance columns) and the clean design's DSL ergonomics onto it.
- Two urgent issues surfaced independent of the redesign: a live bug (Aixle Builder attaches zero meta tools since migration `20260627000002`) and a loose gem pin (`~> 0.100`) that lets `bundle update` break the monkey-patched 4-arg `send_tools_call`.

**Recommendation:** implement the synthesized architecture in five stages (0–4), each independently shippable and revertible: hotfixes + ops hardening → registry + shadow rows behind a byte-parity gate → availability unification → taxonomy cutover behind a kill switch → deferred cleanup and gem decision.

## Table of Contents

1. Research Overview & Scope Confirmation
2. Technology Stack Analysis — current baseline, actionmcp, MCP spec, Ruby ecosystem, Rails registry patterns, agent-platform patterns
3. Integration Patterns Analysis — async execution, container runtimes, metadata trust, availability eventing, gating unification
4. Architectural Patterns and Design — design panel, urgent findings, the synthesized architecture, staged migration, trade-offs
5. Implementation Approaches — testing strategy, observability/audit, rollout/cutover, recommendations & success metrics
6. Research Conclusion

---

## Research Overview

**Topic:** Redesigning the Aixle MCP tool system into a code-first registry: platform tools defined and served from code without DB rows; the DB reserved for user-created (docker-image) custom tools; a clean tagging taxonomy replacing the muddled `kind` enum; and per-tool availability predicates (e.g. hide `slack_post_message` when the project has no active Slack integration).

**Methodology:** A codebase audit (Explore agent over the Rails app) established the current state. Web research was executed as a parallel multi-agent workflow (5 researchers + a completeness critic), with all load-bearing claims verified against primary sources (gem source code, official specs/docs) as of 2026-07-02. Confidence levels are noted where sources are weaker.

## Technical Research Scope Confirmation

**Research Topic:** Aixle MCP code-first tool registry (DB-less platform tools, tagging, availability gating)
**Research Goals:** Code-defined platform tools available without DB rows; DB only for user-created custom tools; tagging/categorization for code tools; per-tool availability predicate gated on project/session integrations; safe migration path accounting for FK references (`tool_results.tool_id`, `session_tools`).

**Technical Research Scope:**

- Architecture Analysis — code-first tool registry patterns, hybrid code+DB catalogs, single-source-of-truth tool definitions
- Implementation Approaches — Ruby DSL design, Zeitwerk-safe registry construction, evolution of existing seeds (`ManagedMCPToolRegistry`, `InternalToolStrategy.define`)
- Technology Stack — actionmcp gem native capabilities vs the monkey-patch, MCP spec dynamics, Ruby MCP ecosystem
- Integration Patterns — availability predicates / capability gating, unification of the three current gating mechanisms
- Migration Path — from seeds + idempotent data migrations to code-first, FK strategy, compatibility

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-07-02

---

## Technology Stack Analysis

### Current Stack Baseline (Codebase Audit)

The `Tool` ActiveRecord model (`app/models/tool.rb`) is today the single source of truth for every callable tool. Key facts established by the audit:

- **Kinds:** `enumerize :kind, in: %i[custom system internal workflow meta]` with semantics scattered across the code: `workflow` tools auto-injected for `workflow_step` sessions, `internal` tools injected when container tools are present, `meta` explicitly excluded from `visible_for_*` scopes, `system` tools surfaced only through managed MCP servers (`TerminalSession#available_tools`, `app/models/terminal_session.rb:130-153`).
- **Definitions are duplicated:** JSON input schemas live in `db/seeds/platform_tools.rb` (~50 seeded platform tools) while behavior lives in `app/services/internal_tools/*.rb` (52 classes), coupled only by the `name → CamelCase` convention in `InternalToolExecutor#resolve_handler`.
- **The gem is bypassed:** `actionmcp` (published gem, pinned `~> 0.100`, resolved 0.104.1) is monkey-patched in `config/initializers/action_mcp_dynamic_tools.rb` — `send_tools_list`/`send_tools_call` are overridden wholesale to serve DB rows per authenticated `TerminalSession`. `app/mcp/tools/` contains only an abstract base class.
- **Three separate gating mechanisms for one idea:** (1) `tools.requires_integration` string column filtered in the `visible_for_project` scope (pickers only — not runtime `available_tools`); (2) Coder's managed MCP server + `Integrations::ManagedMCPToolRegistry` (provider → tool-name list, the only existing in-code registry); (3) in-handler runtime checks (`InternalTools::SlackPostMessage` errors when Slack is absent).
- **FK constraint for any "DB-less" design:** `tool_results.tool_id` and the `session_tools` join table (workflow steps attach tools by id) reference `tools.id`. Platform tools without rows break these references unless the design compensates.
- **Sync machinery to be replaced:** idempotent `find_or_initialize_by(...).update!` seeding (`Seeds::PlatformTools.seed!`, run via `platform_tools:seed` rake on deploy) plus belt-and-suspenders idempotent data migrations (`MigrationTool` pattern).

### ActionMCP Gem: Native Capabilities vs the Monkey-Patch

Latest version is **0.111.1 (2026-06-18)**; the app pins 0.104.1 — 7 minor versions behind, with roughly monthly minor releases (https://rubygems.org/gems/actionmcp, https://github.com/seuros/action_mcp/releases).

**Native tool model (already code-first).** Tools subclass `ApplicationMCPTool < ActionMCP::Tool` with a `tool_name` / `description` / `property` / `collection` / `output_schema` DSL plus MCP annotations (`read_only`, `destructive`, `idempotent`, `open_world`), `meta(hash)`, and consent gating (`requires_consent!`). Registration is load-time autodiscovery: `ActionMCP::Tool.inherited` fires a load hook that registers the class in `ActionMCP::ToolsRegistry` — a process-global, **non-thread-safe** class-level Hash. Classes live in `app/mcp/tools/`, pushed to Zeitwerk with `namespace: Object` and collapsed subdirectories (top-level constants only) (https://raw.githubusercontent.com/seuros/action_mcp/master/lib/action_mcp/tool.rb, engine.rb, registry_base.rb).

**Native per-session scoping exists.** `ActionMCP::Session#tool_registry` (default `["*"]`) stores tool *names*; `session.register_tool`/`unregister_tool` mutate it and emit `notifications/tools/list_changed` (gated on the advertised capability). Since 0.107.0 the official per-request hook `Gateway#configure_session(session)` is the sanctioned place to compute availability. Caveats: `register_tool` refuses names not present in the code registry (DB-only tools cannot enter the native path), the 0.108.0 release fixed a wildcard bug that previously broke `unregister_tool` on fresh sessions, and profile switching primitives are hazardous (`configuration.use_profile` mutates process-global state; blockless `with_profile` leaks a thread-local across pooled requests) (https://github.com/seuros/action_mcp/blob/master/GATEWAY.md).

**No per-tool visibility predicates.** There is no `visible_to?(session)`-style hook; listing = (profile name-list) ∩ (session name-list). Consent is enforced only at call time (confidence: high — verified absent from tool.rb/session.rb/server/tools.rb).

**The monkey-patch remains necessary for DB-backed tools through 0.111.1** — there is no resolver extension point; `send_tools_list`/`send_tools_call` resolve exclusively via registry classes. But the patched surface changed materially since 0.104.1, so upgrading requires rewriting the overrides:

- `send_tools_call` gained a fifth argument (`task_params`) — a 4-arg override raises `ArgumentError` after upgrade.
- `send_tools_list` gained spec-compliant cursor pagination (0.109.0).
- Overrides now silently bypass: task-augmented execution (MCP 2025-11-25 tasks), the consent gate (`-32002`), strict-param errors (`-32602`, 0.111.1), and dev-mode reloader wrapping.
- Protocol versions at 0.111.x: `SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18"]`, default 2025-06-18; **2025-03-26 support was dropped** — clients pinned to it would break on upgrade (verified in `lib/action_mcp.rb`; the README claiming otherwise is stale).
- Gemspec constraints are unchanged (Rails >= 8.1 at both 0.104.1 and master) — no hidden platform upgrade cost.

**Dev-mode constraint for any runtime registration scheme:** the engine's `to_prepare` hook runs `ToolsRegistry.clear!` on every code reload — runtime-registered classes (e.g. built from DB rows) vanish on reload unless re-registered from a `to_prepare` hook; combined with the non-thread-safe registry Hash, registering DB tools into the global registry at request time is unsafe under Puma concurrency (confidence: high for the code, race consequence inferred).

### MCP Specification: Dynamic Tool Lists, Metadata for Tagging, Availability

**Revisions.** Current ratified revision: **2025-11-25**; the **2026-07-28** revision's release candidate is locked (final publication scheduled 2026-07-28) (https://modelcontextprotocol.io/specification/versioning, https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/).

**Per-session dynamic tool lists are spec-blessed — with one new constraint.** Under 2025-11-25 the spec is silent (dynamic per-context lists are established practice; the official TS SDK auto-emits `list_changed` from `tool.enable()/disable()` — confirmed against official SDK docs). The 2026-07-28 RC makes it explicit: the tool set "MAY vary by the authorization presented on the request — for example, returning only the tools the caller's granted scopes permit — since credentials are per-request input, not connection state," but "MUST NOT vary per-connection or as a side effect of other requests on the connection" (https://modelcontextprotocol.io/specification/draft/server/tools). Aixle's model — deriving the list from the authenticated TerminalSession credential on each request — is exactly the blessed pattern; deriving it from connection-local mutations would become non-compliant. The RC also asks for **deterministic tool ordering** (enables client caching and LLM prompt-cache hits) and adds `tools/list` caching metadata (`ttlMs`, `cacheScope: "private"` for per-user filtered lists).

**No first-class tags field exists in any revision.** Tool metadata on the wire: `name`, `title`, `description`, `inputSchema`, `outputSchema`, `annotations` (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint` — display/UX hints, explicitly untrusted), `icons`, `execution.taskSupport`, and the generic `_meta` extension point. `_meta` with a reverse-DNS prefix is the sanctioned way to ship tags (e.g. `"_meta": {"ai.aixle/tags": ["messaging", "slack"]}`); prefixes whose second label is `mcp`/`modelcontextprotocol` are reserved (https://modelcontextprotocol.io/specification/2025-11-25/server/tools, /basic). Ecosystem precedent: FastMCP (Python) tools carry `tags: set[str]` used for server-side filtering, with a v3 visibility API `server.enable(tags=..., only=True)` (https://gofastmcp.com/servers/tools).

**Conditional exposure guidance.** Hiding is not authorization — servers MUST enforce access controls on `tools/call` regardless of what `tools/list` returned. Spec mechanisms relevant to integration gating: filter at list time + emit `list_changed` on availability flips; incremental scope consent via `WWW-Authenticate` (SEP-835); URL-mode elicitation (SEP-1036 — e.g. serve a "Connect Slack" URL mid-interaction instead of hiding); the RC's `input_required` tool results formalize "call → ask for what's missing → retry". Per SEP-1303, input/validation failures should be tool execution errors (`isError: true`) so models can self-correct.

**Client reality check — `list_changed` push is unreliable across the ecosystem; per-request `tools/list` is the only universal mechanism:**

- Claude Code: partial support since 2.1.0 — cross-turn refresh works, same-turn registrations fail ("No such tool available"); consolidated issue closed "not planned" (https://github.com/anthropics/claude-code/issues/31893; confidence: medium-high).
- Cursor: ignores the notification mid-session; list frozen until restart (as of May 2026).
- Anthropic Messages API MCP connector: stateless per request — re-imports tools each request; dynamic lists "just work", `list_changed` moot.
- OpenAI Responses API: caches the `mcp_list_tools` item in conversation context; Agents SDK re-lists per run (optional cache).

Practical rule for the design: compute availability inside the `tools/list` handler from per-request auth state; emit `list_changed` best-effort; make calls to hidden/unavailable tools return a self-describing `isError: true` result ("Slack is not connected for this project — connect it at …").

### Ruby MCP Server Ecosystem Comparison

| Capability | Official `mcp` SDK 0.22.0 | fast-mcp 1.6.0 | ActionMCP 0.111.1 | model-context-protocol-rb 0.7.0 |
|---|---|---|---|---|
| Code-first class registry | Yes (subclasses passed as `tools:` array); no autodiscovery — you assemble the list | Yes + Rails autodiscovery of `ApplicationTool` descendants | Yes + autodiscovery via eager loading | Yes, static `config.registry` block |
| Runtime-dynamic tool set per session/request | **First-class**: new server per request with computed `tools:`; `MCP::Tool.define` / `server.define_tool` for runtime-built tools | Partial: `filter_tools` blocks build a per-request filtered server copy — subtractive only (cannot add DB-built tools) | Partial: profiles (static named sets) + session name-lists; no DB tools | No |
| Tool tagging/grouping | No (build your own) | Yes: `tags :admin` + `metadata` k/v | Profiles as named grouping; no per-tool tags | No |
| Availability predicates | DIY plain Ruby when composing `tools:` (Fleetio's per-user `available_tools` is a live example) | Yes: `server.filter_tools { \|request, tools\| ... }` | Consent gating + profile switching; no per-tool hook | No |
| Transports | stdio, Streamable HTTP (stateless mode; in-memory sessions → single-process/sticky caveat) | stdio, **legacy HTTP+SSE only** (deprecated since spec 2025-03-26) | HTTP JSON-RPC (2025-11-25 + 2025-06-18) | stdio, Streamable HTTP **with Redis multi-process coordination** |
| Protocol versions | 2024-11-05 … 2025-11-25, default latest stable | legacy | 2025-11-25, 2025-06-18 (2025-03-26 dropped) | n/a (README-level) |
| Maintenance (2026-07-02) | Very active (Shopify + MCP org, weekly-ish) | **Idle since 2025-09-28**, 46 open issues | Active (June 2026) | Active (Mar 2026) |

(https://github.com/modelcontextprotocol/ruby-sdk, https://github.com/yjacquin/fast-mcp, https://github.com/seuros/action_mcp, https://github.com/dickdavis/model-context-protocol-rb)

**Migration difficulty signals:**

- **Official `mcp` gem — best structural fit, moderate effort.** Its documented Rails idiom (a controller that builds a **server per request** with a computed `tools:` array, then `StreamableHTTPTransport.new(server, stateless: true).handle_request(request)`) is precisely what the current monkey-patch simulates. Code tools = `MCP::Tool` subclasses passing availability predicates; DB custom tools = `MCP::Tool.define(...)` materialized from rows. No gem internals to override. Costs: auth moves to standard Rails controller auth (`server_context:` carries identity); each `InternalTools::*` service is mechanically adapted; stateless mode forgoes server-initiated per-session streams. A production write-up (Fleetio, 2026-03) demonstrates the full pattern including per-user tool lists (https://developer.fleetio.com/blog/setting-up-and-securing-an-mcp-server-in-rails).
- **fast-mcp — poor fit despite on-paper match** (tags + `filter_tools`): filters are subtractive over a boot-time registry (DB tools can't be injected per request), transport is legacy-only, and the project is unmaintained.
- **Staying on actionmcp (upgraded to 0.111.x) — lowest churn, but the patch persists** and must be rewritten against 7 versions of internal churn (signature change, pagination, tasks, consent, strict params).

### Registry Patterns in the Rails Ecosystem (code-first + DB hybrid)

The ecosystem has converged on two safe registry shapes — (a) **`eager_load_namespace` + `descendants` at query time** (Shopify maintenance_tasks, Avo, ViewComponent) and (b) **explicit registry rebuilt on every boot/reload from an initializer** (Flipper groups, GoodJob cron, ActiveAdmin). Nobody stores class objects in a long-lived registry populated once at boot in dev.

- **Flipper** — the cleanest "availability predicate" prior art: DB/adapter rows store only group *names*; predicate blocks are registered in code (`Flipper.register(:admins) { |actor| ... }`) and rebuilt every boot, so they can never go stale (https://www.flippercloud.io/docs/features/groups).
- **Solid Queue** — *literally Aixle's hybrid in production Rails*: static recurring tasks come from config, dynamic ones from runtime API, both in **one table with a `static` boolean discriminator**. At scheduler boot, config is reconciled into mirror rows: `RecurringTask.static.where.not(key: static_task_keys).delete_all` + `upsert_all(..., unique_by: :key)`. Execution records reference tasks by **string `task_key`, not FK id** — even though rows exist (https://github.com/rails/solid_queue/blob/main/lib/solid_queue/scheduler/recurring_schedule.rb).
- **GoodJob** — the no-mirror-rows alternative: cron entries exist only in config; runtime enable/disable state lives in a generic `Setting` KV row holding arrays of key strings; job rows carry a `cron_key` string column with a unique `[cron_key, cron_at]` index (https://github.com/bensheldon/good_job).
- **maintenance_tasks (Shopify)** — string-name references done rigorously: `Run.task_name` resolved via `safe_constantize` with a typed `NotFoundError`; existence validated at create time; discovery = `Rails.autoloaders.main.eager_load_namespace(namespace)` then `descendants` (https://github.com/Shopify/maintenance_tasks).

**Zeitwerk-safety rules** (from the Rails autoloading guide and Zeitwerk README): "do not cache reloadable classes or modules" — a `{name => Class}` hash built in an initializer holds stale classes after the first dev reload; rebuild in `to_prepare` (idempotently — it can run twice), or store **string class names resolved via `safe_constantize` at call time** (zero reload hazard), or use `autoload_once_paths`, or compute `descendants` at request time after `eager_load_namespace`. Zeitwerk's `on_load`/`on_unload` hooks exist specifically for incremental registry maintenance (https://guides.rubyonrails.org/autoloading_and_reloading_constants.html, https://github.com/fxn/zeitwerk).

**Virtual-record options for the code side:** FrozenRecord and ActiveHash give AR-like APIs over in-code data, but both would recreate the drift problem one layer over (a YAML manifest parallel to the handler classes) or couple DB FKs to hand-maintained integer ids. The pattern the surveyed gems actually use is **duck-typed POROs/classes unified with AR rows at the query layer** — both sides respond to `#name`, `#description`, `#input_schema`, `#tags`, `#available?(context)` and the list handler concatenates them (GoodJob's `CronEntry` PORO listed alongside job rows is the exemplar).

**FK strategies for rows referencing code-defined tools, ranked by ecosystem prevalence:**

1. **String-key references** (dominant): `tool_key` string column; resolution at read time; orphaned rows error visibly at resolution (maintenance_tasks, GoodJob, Solid Queue executions, Flipper, Rails STI itself).
2. **Shadow/mirror rows + boot-time reconcile** (Solid Queue `persist_static_tasks`): keeps real FKs working; the closest evolution of Aixle's current seeds — formalize seeding as an idempotent boot reconcile instead of migrations.
3. **Single-table discriminator** (`static`/`source` column): platform rows owned by the reconciler, custom rows by users; existing `tool_id` FKs keep working unchanged.
4. Integer FK into in-code data (ActiveHash) — fragile ids; string keys strictly safer.

**Drift detection:** Solid Queue prevents drift (authoritative overwrite at boot); maintenance_tasks validates at create-time only; the Rails pending-migration machinery (`check_all_pending!`, `db:abort_if_pending_migrations`) is the UX template for an Aixle `tools:check` CI task diffing registry keys vs DB rows.

### Tool Registry Patterns in Agent Platforms

**Dify implements exactly the target split** (verified in `api/models/tools.py`): code/plugin-defined built-in tools have **no DB row for their definition** — a `BuiltinToolProvider` row exists only to store a tenant's encrypted credentials (no credentials → no row → provider unauthorized); user-created tools (`ApiToolProvider`) store the full user-authored definition (OpenAPI schema, tool list JSON, credentials) in the DB. Plugin definitions co-locate everything in code: provider YAML (identity, **16-value fixed tag vocabulary**, typed credential spec) + per-tool YAML (with an explicit `description.human` vs `description.llm` split) + the Python handler class beside them (https://raw.githubusercontent.com/langgenius/dify/main/api/models/tools.py, https://docs.dify.ai/en/develop-plugin/dev-guides-and-walkthroughs/tool-plugin).

**Availability predicate signatures across platforms** — predicates consistently receive *(run/session context, tool/agent identity)* and return bool:

| Platform | Signature | Hide or block? |
|---|---|---|
| OpenAI Agents SDK | `is_enabled: bool \| (RunContextWrapper, AgentBase) -> bool` (sync/async) | Hidden from the LLM entirely |
| OpenAI Agents SDK (MCP) | dynamic filter `(ToolFilterContext, tool) -> bool` with `run_context`, `agent`, `server_name` | Hidden |
| LangChain 1.0 middleware | `wrap_model_call` + `request.override(tools=...)` — filter-down only, cannot add mid-run | Hidden per model call |
| Dify | provider-level `_validate_credentials` + credential-row presence | **Visible but unusable** until authorized |
| LibreChat | credential presence (admin env var OR per-user encrypted record) | Hidden if no credential |
| Zapier MCP | explicit per-server action enablement + connected accounts | Hidden (deny-by-default) |
| Composio | connection status returned *with* search results; `COMPOSIO_MANAGE_CONNECTIONS` starts auth | **Exposed with "not connected" + connect affordance** |

(https://openai.github.io/openai-agents-python/tools/, https://blog.langchain.com/agent-middleware/, https://docs.composio.dev/docs/tools-and-toolkits)

The one genuine design fork: **hide vs expose-with-affordance**. OpenAI SDK/LibreChat/Zapier hide unavailable tools (keeps the model from attempting doomed calls); Dify/Composio keep them discoverable and surface an authorize/connect action (lets the agent itself prompt the user to connect the integration). Both are well-attested; MCP's URL-mode elicitation makes the affordance path spec-native.

**Tag taxonomy consensus — three orthogonal axes recur in the wild:**

1. **Domain/category** — small closed vocabularies, not free-form (Dify: 16 tags; n8n codex: 10 exact-match categories + `subcategories`/`alias` for search).
2. **Provider/service grouping via namespacing**, not tags: `mcp__slack__*`, `GITHUB_CREATE_ISSUE`, `slack_` prefixes. Anthropic's tool-search guidance: "prefix by service (`github_`, `slack_`) so one search matches the whole group". Claude Code's permission grammar globs over the same namespace, and a bare tool-name deny *removes the tool from context entirely* — clients already distinguish hiding from blocking.
3. **Behavior/risk hints** as a separate axis — MCP `ToolAnnotations` (`readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint`), used by clients for confirmation policies.

Cautionary counter-example: LangChain's `tags`/`metadata` are plumbed only into tracing callbacks, not model-visible selection — nobody uses them as a registry taxonomy. Tags must *do* something (filtering, gating, grouping) or they rot.

**Deferral is orthogonal to availability:** Anthropic's `defer_loading` + Tool Search (accuracy degrades past ~30–50 tools; use search from ~10+ tools) and Claude Code's auto tool-search treat "available but deferred" as a distinct state — worth keeping as two separate flags in the registry design (https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool).

### Technology Adoption Trends and Implications

- The ecosystem direction is **stateless, per-request-computed tool lists** (MCP 2026-07-28 RC stateless core; Anthropic connector re-importing per request; official Ruby SDK's server-per-request idiom). Aixle's TerminalSession-key-per-request model is already aligned; the redesign should compute availability in the list handler, not via connection-state mutation.
- **Single source of truth in code** (schema + handler + metadata + availability co-located) with **DB rows storing only tenant state or user-authored definitions** is the cross-platform consensus (Dify, OpenHands, LibreChat).
- **String keys, never FKs, from DB rows to code-defined entries** is the dominant Rails pattern; shadow rows with a discriminator (Solid Queue) is the sanctioned variant when existing FKs must survive — directly applicable to `tool_results`/`session_tools`.
- Open follow-ups routed to later steps: (a) execution/isolation architecture for docker-image custom tools (Dify's plugin daemon — subprocess/TCP/Lambda runtimes — is the reference architecture; needs its own pass); (b) trust/sanitization of user-authored tool names/descriptions sharing a `tools/list` with platform tools (name-collision/shadowing, description-based prompt injection; reserve platform prefixes, validate against the spec's `[A-Za-z0-9_.-]` name guidance).

_Primary sources: gem source code (action_mcp, solid_queue, good_job, maintenance_tasks, ruby-sdk, fast-mcp — raw.githubusercontent.com), modelcontextprotocol.io spec pages (2025-11-25 + draft), rubygems.org, Rails autoloading guide, Zeitwerk README, official platform docs (Dify, OpenAI Agents SDK, Anthropic, LibreChat, n8n, Composio)._

---

## Integration Patterns Analysis

### Async Tool Execution over MCP: the `execution_id` Pattern vs Spec Tasks

**Headline: the current `execution_id` + `read_tool_result` pattern is the only interop-safe mechanism in mid-2026, and the spec alternative is a moving target.** The MCP 2025-11-25 experimental Tasks API (SEP-1686 — task-augmented `tools/call` returning a task handle, `tasks/get`/`tasks/result`/`tasks/cancel`, per-tool `execution.taskSupport`) is being **superseded by SEP-2663** (merged 2026-05-15, final 2026-07-28): tasks move out of core into an extension with a redesigned lifecycle — *server-directed* creation (`tools/call` may answer with `resultType: "task"`), non-blocking `tasks/get` + `tasks/update`, `tasks/list` removed. The MCP blog states verbatim: "Anyone who shipped against the 2025-11-25 experimental Tasks API will need to migrate to the new lifecycle" (https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/ — verified; confidence: high).

**No mainstream host sends task-augmented calls today:** Claude API MCP connector — "only tool calls are currently supported"; Claude Code — async MCP execution listed as not implemented (issue #31893, closed "not planned"); OpenAI — tools-only, its async story is API-level background mode; Cursor — long calls >~30s reportedly mishandled (confidence: medium, forum-sourced).

The polling pattern is well-attested prior art, not a hack: AWS's "Async HandleId" pattern, Arcade.dev's "Async Job" pattern (#54 patterns write-up), n8n's execute-workflow returning an execution id. Documented agent-UX pitfalls to harden against: agents forget to poll or hallucinate job IDs; hallucinated completion without deterministic status; poll loops burning turns. Mitigations (all verified recommendations): echo the execution_id + original request context + poll-interval hint in every `read_tool_result` response; idempotency keys on dispatch; durable job store (Temporal + DB already satisfy the latter two).

**actionmcp's tasks implementation is not a safe bet:** 0.104.1 reads task augmentation from the wrong place (`params._meta["task"]` instead of top-level `params.task`), `tasks/result` doesn't block as the spec requires, and wire-format drift (emits `id` not `taskId`, nonstandard `progress` object). The gem shows no SEP-2663 adoption through 0.111.1 (changelog verified). If tasks are ever wanted, the `Session::Task` row is executor-agnostic (any process can drive `complete!`/`mark_failed!`), but dispatch is hard-coded to `ToolExecutionJob.perform_later` — a Temporal-backed executor requires patching `handle_task_augmented_tool_call`.

**Operational details that must be first-class in the design:**

- **Temporal cancellation requires heartbeats:** "Activities must heartbeat to receive cancellations" — a non-heartbeating activity never observes the cancel (https://docs.temporal.io/activity-execution). The docker-running activity must heartbeat on an interval, set a Heartbeat Timeout, and on cancel actually `docker kill` the container — otherwise cancellation flips workflow state while the container keeps running.
- **Result size limits:** Claude Code warns when MCP tool output exceeds 10,000 tokens (`MAX_MCP_OUTPUT_TOKENS`). `read_tool_result` needs truncation/pagination (offset/tail semantics) as a first-class feature (https://code.claude.com/docs/en/mcp).
- **Long sync calls, if ever preferred:** Claude Code aborts a remote call idle >5 min unless progress notifications arrive (`CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`), but the per-server `timeout` is a hard wall-clock cap that progress does **not** extend. actionmcp 0.104.1 emits no `notifications/progress` during `tools/call`.
- **`resource_link` alternative, named and dismissed:** a tool could return `{"type": "resource_link", "uri": ...}` pointing at the pending result; client support for resource subscription is even weaker than for `list_changed`, so it does not change the recommendation.

### Container Execution Architecture for Custom Tools

**Reference architecture — Dify plugin daemon:** one daemon HTTP contract fronts three interchangeable runtimes (local subprocess over STDIN/STDOUT, debug TCP, AWS Lambda invoked over HTTP) — the caller never knows which runtime served the call; Dify SaaS runs 2,300+ Lambda functions handling 1M+ plugin calls/month (https://github.com/langgenius/dify-plugin-daemon, https://aws.amazon.com/solutions/case-studies/dify-lambda-case-study/). The stable interface is the *invocation contract*, not the runtime — the same principle behind keeping Aixle platform tools in-process while custom docker tools go through Temporal. Notably, self-hosted Dify does **not** sandbox local plugins (signing + review instead) — Aixle's docker-per-execution model is already stronger; the gap is hardening, not architecture.

**Lifecycle models in the wild:** per-invocation serverless (Dify/Lambda, AWS Bedrock AgentCore's one-session-one-microVM) vs persistent sandbox (Daytona, OpenHands container-per-session, Claude Code devcontainer). Aixle's execute→poll pattern matches the per-invocation model, so **credentials should be minted/injected per execution and die with it**. Isolation consensus: plain Docker (shared kernel) is not an adequate boundary for untrusted multi-tenant code; production anchors are Firecracker (E2B, Fly, Lambda, AgentCore), gVisor (Modal), Docker+optional Kata (Daytona). Even managed products get egress wrong (Unit42 bypassed AgentCore's network isolation) — treat network policy as defense-in-depth.

**Docker-level hardening baseline** (OWASP Docker Security Cheat Sheet): non-root/userns-remap, `--cap-drop all`, `--security-opt=no-new-privileges`, seccomp/AppArmor, `--memory`/`--cpus`/`--ulimit nproc`, `--read-only` root FS + tmpfs, no default bridge. Registry-level: scan-on-push + severity-threshold pull blocking (Harbor/Trivy pattern), image signing (Cosign), and **digest pinning** — store the image digest on the Tool row at registration, run by digest, rescan on schedule (synthesis; controls verified individually).

**Credential injection:** env vars are the weakest option (visible in `/proc/<pid>/environ`, `docker inspect`, inherited by children, commonly logged); mounted tmpfs files are better; the emerging pattern is egress-proxy credential brokering — the secret never enters the sandbox, a proxy injects it on outbound requests (E2B's per-host header-injection egress transforms; open E2B issue #1160 requesting full brokering). Aixle's `ConfigItem` decryption into container env (`CustomToolStrategy#build_env_vars`) is the current baseline; per-execution short-lived credentials (Vault dynamic-secrets model) are the upgrade path. "Environment variable leakage is the biggest security blind spot in agent sandboxing" (https://manveerc.substack.com/p/ai-agent-sandboxing-guide).

**Getting files into containers:** OpenHands builds a derived image layer over the user's base image (three-tier tag caching) rather than copying at start; Aixle's docker-archive-API injection (`store_tool_files`) matches the lighter-weight alternative. Both are attested; image-layer derivation pays off when tool files are stable across executions.

### Trust and Sanitization of User-Authored Tool Metadata

**The threat is concrete and current.** Tool Poisoning Attacks (Invariant Labs, April 2025): instructions embedded in tool `description` fields that the model reads but UIs hide — demonstrated exfiltrating SSH keys via Cursor; the WhatsApp-MCP "sleeper" attack showed post-approval mutation and cross-tool shadowing (a malicious tool's description manipulating how a *trusted* tool behaves) (https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks, https://invariantlabs.ai/blog/whatsapp-mcp-exploited). A vendor scan of the top-100 Smithery servers flagged 22 with metadata findings (single-source; directionally useful, not established fact).

**Aixle-specific framing:** platform tools (Ruby classes) are immune; **user-created custom tools are exactly the TPA vector** — their descriptions and schema sub-descriptions are tenant-author-controlled text co-listed with trusted tools in one `tools/list`. Cross-server shadowing collapses into *intra-list* shadowing with no server boundary for the client to distrust. The rug-pull surface is the DB: any UPDATE to a custom-tool row is a potential silent redefinition.

**Spec facts (verified against live 2025-11-25 spec):** tool names SHOULD be 1–128 chars, case-sensitive, `[A-Za-z0-9_.-]` (no slash — the SEP-986 page saying 1–64+slash is stale), unique within a server; uniqueness across servers/tenants is entirely the implementer's problem; SEP-986 explicitly declares "Security Implications: None" — **names are not a trust boundary**. `inputSchema` MUST be valid JSON Schema (2020-12 default); real-world breakage: a root-level `$ref` or dangling `$ref` in one user schema can break clients' loading of the *entire* tool list (FastMCP issue #2455); `$dynamicRef`/`$defs` are rejected by several client validators.

**Policy checklist for the mixed multi-tenant list** (items 1, 3, 5-output-scope, and rate-limits per OWASP/spec; namespace-prefixing, collision/substring rejection, schema size caps, and per-session tool-count caps are sound *synthesis*, not OWASP text — attribution corrected per verification pass):

- *At creation (expensive, one-time):* enforce the spec name regex; **force a reserved tenant namespace on user tools** so the DB emit-path physically cannot produce a platform tool name (and reject collisions/substring matches with platform names); meta-validate schemas against the 2020-12 meta-schema, reject or fully dereference `$ref`/`$defs`/`$dynamicRef`; cap schema size/depth/property count; require `additionalProperties: false`; sanitize ALL free text including nested schema descriptions/titles/enum labels (strip `<IMPORTANT>`-style tags, flag imperative injection patterns); optionally run an MCP-Scan-style metadata classifier; **store a content hash of the full definition** (tool pinning); for docker tools — ephemeral build-and-list gate + pin to image digest, never mutable `:latest`.
- *At list time (cheap, per-request):* re-verify the definition hash (defeats DB-side rug pulls); filter by session entitlement + integration predicates; emit user tools only under their namespace prefix.
- *At call time (enforce, don't trust):* validate args against the meta-validated schema; per-tenant/per-tool rate limits and quotas; **sanitize tool output before it re-enters LLM context — including the `read_tool_result` payload from Temporal-run containers**, not just sync responses; audit-log every call with provenance and full parameters.

### Propagating Integration State into Tool Availability

**Universal pattern (high confidence): recompute availability on every `tools/list`/`tools/call` from current DB state; treat `list_changed` as a best-effort hint, never load-bearing.** Shipping examples: GitHub's remote MCP server resolves toolsets/read-only/flags from request headers on every request, stateless; Composio recomputes at meta-tool call time ("tool availability updates immediately after authentication"); Zapier accepts stale client lists and tells users to click Refresh. Client-support gaps for `list_changed` are extensively documented (Claude Desktop, Gemini CLI, LibreChat, VS Code mid-conversation).

**Aixle's advantage:** the Integration row lives in the local DB, so connect/disconnect is a local write — an `after_commit` on Integration status changes can broadcast `list_changed` to live TerminalSessions (cheap, spec-SHOULD), while per-request recomputation remains authoritative. One gap the audit exposed: Aixle owns its Slack app, so it must consume **Slack's `tokens_revoked` and `app_uninstalled` events** (delivery order between them is not guaranteed; `tokens_revoked` does not fire for channel-scope revocations) — otherwise the Integration row stays `active` after a workspace uninstall and the predicate serves dead tools (https://docs.slack.dev/reference/events/tokens_revoked/). Coder is self-hosted per-deployment; health-check polling is likely the only revocation signal (open item).

**Predicate evaluation cost (Rails-specific):** one batched query per request — `Integration.active.where(company/project scope).pluck(:provider, ...)` into an in-memory Set — then evaluate every tool's predicate against it; never one query per tool. Memoize via an `ActiveSupport::CurrentAttributes` **declared attribute** (the thoughtbot incident: caching in an undeclared ivar on a CurrentAttributes subclass leaks across requests). Flipper's preload-all-features middleware is the same shape and the prior art. Caveat: CurrentAttributes reset assumes the Rack executor — long-lived SSE streams and Temporal activity threads need explicit set/reset wrapping.

**Scope→tool declaration prior art:** in every observed system the requirement is *static per-tool metadata* (GitHub MCP tools declare required OAuth scopes; Atlassian groups tools into admin-granted permission groups), and only the *evaluation strategy* varies: filter-at-list (GitHub PAT mode — hide) vs challenge-at-call (GitHub OAuth mode — expose all, return a scope challenge, GA Jan 2026). This maps directly onto Ruby tool classes declaring `requires_integration :slack` as class metadata.

**Evidence against agent-driven toolset toggling:** GitHub built `--dynamic-toolsets` (meta-tools to enable toolsets on demand) and **deleted it** (PR #2512, merged 2026-05-20) — local-only, never offered remotely, real complexity. Static declarative filtering won.

**Feature flags as an orthogonal layer:** availability = `integration_connected?` (capability, DB fact) AND `flag_enabled?(tool, actor: company)` (policy — gradual rollout, kill switch). Flipper's actor model (`Company:123`) + preload middleware adds ~zero marginal queries. GitHub's own MCP feature-flag system (per-request `X-MCP-Features` header changing the tool inventory) is shipping prior art.

**Unavailable-tool UX for agent-facing surfaces:** default to **hiding** integration-gated tools (smaller lists measurably help agents), but pair with an actionable call-time error since agents may act on stale lists. The critic resolved an important line the researchers missed: **return the actionable `isError: true` result ("Slack is not connected for this project — connect it at …") only for entitled-but-disconnected tools; return a plain protocol unknown-tool error for tools outside the tenant's entitlement scope** (cross-tenant tools, flag-disabled tools) — otherwise the remedy message leaks capability existence across the entitlement boundary. "Show-disabled-with-reason" in the list itself has no protocol support and no observed adopter.

### Unifying Aixle's Three Gating Mechanisms (synthesis)

The audit found three mechanisms expressing "this tool needs integration X": the `requires_integration` column (pickers only), the managed-MCP-server + `ManagedMCPToolRegistry` path (Coder), and in-handler runtime checks (Slack). The research supports collapsing them into one model:

1. **Declaration:** static class-level metadata on the tool (`requires_integration :slack`), mirroring GitHub/Atlassian practice — one place, versioned with the handler code.
2. **Evaluation:** a single `available?(context)` predicate evaluated per request in both `tools/list` (hide) and `tools/call` (enforce + actionable error), fed by one batched, request-memoized integration query. The same predicate serves UI pickers — deleting the scope-vs-runtime divergence.
3. **Eventing:** `after_commit` on Integration → best-effort `list_changed`; Slack revocation events keep the Integration row truthful.
4. **Policy layer:** Flipper flags per company for rollout/kill-switch, AND-ed with the capability predicate, never conflated with it.

Open items carried to the architecture step: per-tenant concurrency/quota policy for container executions (fleet fairness, queue vs reject); protocol-version negotiation matrix across hosts; Coder-side managed-server naming/collision semantics.

---

## Architectural Patterns and Design

### Method: Independent Design Panel

Three architects designed the full system independently from different lenses — **A: minimal churn** (evolve in place, shadow rows, staged rollback), **B: clean target state** (single source of truth, string keys, official `mcp` gem), **C: risk-first** (derive from the threat model, structural trust boundaries). Three judges with distinct mandates (maintainer, SRE, security) scored all designs against six criteria, each judge required to verify load-bearing claims against the actual code before scoring.

**Verdict: A wins 2–1** (maintainer and SRE for A; security for C), with near-identical graft lists across all three judges: *adopt A as the base, graft C's structural security controls and B's DSL ergonomics*. B was consistently punished for its irreversible Stage-5 data migration (delete platform rows, rewrite tenant JSONB `tool_ids`) and a self-admitted CurrentAttributes leak hazard; C for concept count and a works-in-dev/breaks-in-prod reconcile gap — but its security model was rated strictly best (10/10, security judge: "the only design where the multi-tenant trust boundary is structural rather than validation-dependent").

### Urgent Findings (independent of the redesign)

The panel's code reads surfaced two production-relevant issues to act on now:

1. **Live bug — Aixle Builder attaches zero meta tools.** `aixle_builder_controller.rb:24` queries `Tool.where(kind: :workflow, name: meta_names)`, but migration `20260627000002` moved `meta_*` rows to `kind: :meta`; additionally `SessionService#scoped_resources` filters attachments through `visible_for_project`, which excludes `:meta`. Verified by two agents independently. Needs staging verification + hotfix regardless of this redesign.
2. **Loose gem pin — `Gemfile` says `~> 0.100`** (resolves 0.104.1 today). Any `bundle update` can jump to 0.111.x, where `send_tools_call` takes 5 args — the 4-arg monkey-patch override raises `ArgumentError` and breaks the MCP server. Pin exactly (`= 0.104.1` or `~> 0.104.0`) with a comment, immediately.

### The Synthesized Architecture (A + grafts)

**Core idea:** definitions move onto the existing `InternalTools::*` handler classes as a `tool do ... end` DSL block — *writing the handler class IS the registration*. The `tools` table keeps every existing FK via Solid Queue-style **shadow rows**: a `source` column (`"code"` / `"db"`) discriminates reconciler-owned projections from user-authored custom tools. Serving metadata always prefers the in-code definition (a stale row can never serve a stale schema).

**1. Definition DSL (with B's param sugar grafted):**

```ruby
module InternalTools
  class SlackPostMessage < Base
    tool do
      display_name "Slack Post Message"
      description  "Send a Slack message from this workflow..."
      tags         :messaging, :slack
      inject_when  :workflow_step_session       # replaces kind: :workflow auto-injection
      requires_integration :slack               # replaces column + in-handler check + registry
      read_only false                           # graft from B: MCP behavior annotations on the wire
      param :text,    type: :string, description: "Message text. Optional when files are provided."
      param :channel, type: :string, description: "..."
      # input_schema(raw_hash) remains the escape hatch for complex shapes
    end

    def execute = ... # unchanged handler body; in-handler check stays as call-time defense in depth
  end
end
```

Every current `kind` maps mechanically: `internal` → `inject_when :container_tools_present` / `:non_interactive_session`; `system` (Coder) → `managed_mcp_provider :coder` + `requires_integration :coder`; `meta` → `tags :builder` + `user_attachable false`.

**2. Discovery — Zeitwerk-safe registry** (`eager_load_namespace(InternalTools)` + `descendants`, memoizing only **frozen `Definition` POROs holding class-name strings** — never class objects; memo reset in `to_prepare`; duplicate names raise at build). Deliberately avoids actionmcp's process-global, non-thread-safe, dev-reload-wiped `ToolsRegistry`. Handler resolution constantizes at call time (maintenance_tasks pattern).

**3. Shadow rows + reconciler (Solid Queue pattern):** `Tools::Reconciler.run!` upserts one row per definition (target: a **new partial unique index `ON tools(name) WHERE source='code' AND deleted_at IS NULL`** — required because the existing NULLs-distinct `(scope_type, scope_id, name)` index does not enforce platform-name uniqueness), and soft-deletes rows for removed definitions (never hard-deletes — `tool_results` FK is RESTRICT). Runs at: (a) deploy via the existing `platform_tools:seed` rake name (pipeline unchanged), (b) boot self-heal under a pg advisory xact lock with column-existence guard and ENV kill switch, (c) lazy `Tool.shadow_for(defn)` fallback materializing a row on first FK need — so "the class alone suffices" is literally true and the seeds file + idempotent-data-migration pattern for new tools dies.

**4. Tagging taxonomy — orthogonal axes replacing `kind`:**

| Axis | Storage | Purpose |
|---|---|---|
| `source` (`code`/`db`) | column | ownership: reconciler projection vs user-authored; drives `platform_tool?`, scope validation |
| `user_attachable` boolean | column (projected) | replaces the `:meta` picker exclusion |
| `tags` (closed vocabulary: `board`, `workflow_control`, `session_lifecycle`, `async_results`, `messaging`, `slack`, `coder`, `builder`) | jsonb column + definition | grouping/lookup (Builder attaches `tagged(:builder)`), UI facets, `_meta["ai.aixle/tags"]` on the wire |
| injection rules (`workflow_step_session`, `container_tools_present`, `non_interactive_session`) | **code only** | replaces kind-driven auto-injection in `available_tools` |
| `managed_mcp_provider` | **code only** | replaces `Integrations::ManagedMCPToolRegistry` |
| behavior annotations (`read_only`, `destructive`, `idempotent`, `open_world`) | definition, serialized to MCP `annotations` | graft from B — client confirmation policies |

**5. Availability — one declaration, one predicate, three evaluation points.** `Tools::Context` batches **one** `Integration` query per request, memoized *on the ctx object itself* (deliberately not CurrentAttributes — the thoughtbot leak incident + SSE/Temporal threads escaping Rack reset). `Definition#available?(ctx)` = integration check AND optional lambda escape hatch (Flipper policy layer ANDs in later, never conflated). Evaluated at:
- `tools/list` — hide unavailable tools; deterministic name sort (2026-07-28 RC guidance);
- `tools/call` — resolve against the unfiltered entitled set, then split per the entitlement rule: entitled-but-disconnected → actionable in-band error ("Slack is not connected… connect it in Project Settings"); not entitled/unknown → `method_not_found`, leaking nothing;
- UI pickers — `visible_for_project` keeps its existing SQL clause over `requires_integration`, but the column is now a **reconciler-owned projection of the declaration** — which is what actually kills the three-mechanism divergence.

**6. Structural anti-shadowing (grafts from C, endorsed by all judges):**
- Call-resolution order fixed as **managed namespace → platform registry → DB custom** — a tenant row physically cannot answer a platform or managed name, even a grandfathered duplicate;
- DB `CHECK` constraint banning `mcp__%` names on `tools` + rejection of the `mcp__` prefix and registry-name collisions in custom-tool validation (the current name regex permits both today);
- `tool_results.tool_key`/`tool_source` provenance columns (additive, backfilled) so history survives row churn and shadow rows can be retired years later without another schema change;
- `tools:check` drift task in CI **and scheduled in prod**: registry-vs-rows diff, custom-name collisions, schema meta-validation with root-`$ref` rejection, step references to soft-deleted rows;
- (follow-up) route custom-tool writes through a Publisher with `definition_digest` pinning + docker image digest pinning — DB rug pulls fail closed.

**7. MCP serving path:** keep actionmcp 0.104.1 + the monkey-patch shape now (all new logic lives in gem-agnostic `Tools::*`); managed Coder namespacing unchanged on the wire; `ManagedMCPToolRegistry` becomes a one-release shim then dies. **Stage-4 option endorsed by all judges:** when the upgrade debt comes due, swap to the official `mcp` gem's stateless server-per-request controller (B's shape, dual-mounted with a transitional route + per-company canary) instead of rewriting the patch against 0.111.x internals.

**8. Per-tenant execution quotas (gap research, verified against Temporal docs):** three layers — (1) dispatch-time Postgres slot counter per company (primary; matches SolidQueue/Sidekiq-Ent semaphore practice; Temporal has no built-in per-tenant concurrency cap — issue #7666 open); (2) Temporal **Task Queue Fairness** with `fairness key = company_id` as the backlog backstop (self-hosted: `matching.enableFairness`); (3) worker tuner as the global infrastructure cap. At the cap: bounded queue with position feedback (~5 running + 10 queued per company), then fast structured rejection with retry-after — agents degrade badly on unbounded latency. Timeouts: docker activity `StartToCloseTimeout` ≈ max tool runtime, short `HeartbeatTimeout` with heartbeats from the container-polling loop (also the cancellation-delivery prerequisite), workflow execution timeout 15–30 min, per-tool configurable timeout column with a platform max.

### Staged Migration (each stage independently shippable, rollback = revert)

- **Stage 0 (this week, independent):** Builder `kind` hotfix + regression tests; exact-pin actionmcp; ops bundle — Slack `tokens_revoked`/`app_uninstalled` consumers, `read_tool_result` truncation/paging, Temporal heartbeats + docker-kill-on-cancel.
- **Stage 1 (no serving change):** `source`/`user_attachable`/`tags` columns + partial unique index (with duplicate pre-check) + backfill; DSL + Registry + Reconciler + `shadow_for` + collision validation + `tools:check`; port ~50 seed entries into `tool` blocks; **bidirectional golden parity gate** (every seeded row ↔ matching definition, full wire-visible fields) then delete the seeds file. `platform_tools:seed` repointed at the reconciler.
- **Stage 2:** `Tools::Context` + `available?` wired into list/call; `requires_integration` becomes reconciler-owned; Coder tools gain the declaration (the one intended behavior change: hidden without a Coder integration).
- **Stage 3:** `available_tools` rewritten on injection rules behind an env kill switch for one release; Builder attaches via `tagged(:builder)`; kind-based scopes → tag/source equivalents; `visible_for_project` → `source`/`user_attachable`. Reconciler keeps writing legacy `kind` through this stage so every rollback lands on rows old code fully understands.
- **Stage 4 (each independent):** drop `kind` (ignored_columns → remove); gem decision (official `mcp` gem server-per-request, or actionmcp 0.111 rewrite); optional `container do ... end` DSL for container-mode platform tools; Flipper policy layer; Publisher digest pinning.

### Honest Trade-offs

Shadow rows are *synced* duplication (machine-owned, drift monitored), not *authored* duplication — the human failure mode is gone, which is the actual goal. Rows remain required for attach-by-id UX (`session_tools`, `steps.tool_ids` jsonb); true row-less serving was judged not worth touching every workflow/picker path. Renames still need data migrations (id continuity) — the registry kills the create/update migration class, not the rename class. The monkey-patch lives until Stage 4, exact-pinned. Accepting string tool keys (`platform:<name>`/`custom:<id>`) in **new** workflow/step configs (dual-read) is the endorsed gradual exit path from integer ids without migrating existing JSONB.

_Full design documents (A/B/C), judge scorecards, and the quotas research are preserved in `ai/research/technical-aixle-mcp-tool-registry-appendix-2026-07-02/`; this section is the synthesis._

---

## Implementation Approaches and Technology Adoption

### Testing Strategy (patterns verified against shipping gems)

**Reconciler tests — copy Solid Queue's shapes** (read directly from `test/integration/recurring_tasks_test.rb`): (a) an `assert_registry_tools(expected)` helper comparing DB rows key-by-key; (b) a **convergence-after-drift test** — mutate a shadow row directly, re-run reconcile, assert the definition wins (this is the shape Solid Queue uses, not just first-boot insert); (c) a removal test — delete a definition, assert soft-delete; (d) a **concurrency test** — run two reconcilers simultaneously, assert no duplicates (validates the advisory lock); (e) an inline golden list of all 52 tool names for discovery completeness (maintenance_tasks' `.load_all` test shape), or a filesystem cross-check (`Dir.glob` handler files vs `Registry.names` — no list to maintain). Notably, none of the surveyed gems use golden files for reconcile logic — inline expected-state hashes + dummy classes.

**Stage-1 parity gate:** freeze the current `Seeds::PlatformTools` output as a **committed fixture before deleting the seeds file**; normalize both sides to canonical JSON (sorted names, sorted keys); assert per-record in a loop so failures name the tool, plus a keys-equality assertion for missing/extra tools; regenerate only via an explicit env var (the approvals-gem workflow — `approvals` 0.1.7 is alive and minitest-compatible). Delete the parity test after the legacy path is removed — it is scaffolding. For the highest-traffic path (`available_tools` rewrite), **github/scientist** is the runtime-parity option: run legacy and new paths side-by-side in production and publish mismatches — maps 1:1 onto the planned env-flagged fallback.

**Zeitwerk/CI:** `config.eager_load = ENV["CI"].present?` in test.rb (Rails 7+ default), the guide's verbatim smoke test (`assert_nothing_raised { Rails.application.eager_load! }`), and `bin/rails zeitwerk:check` as a CI step. Zeitwerk's `eager_load_namespace` is deliberately permissive (silently does nothing if the namespace isn't managed) — the completeness test is what catches a silent miss. All of this slots into the existing `docker compose exec -T web make check_all` gate.

**Pinning the monkey-patch surface** (Arkency's "six ways" + AppSignal/Shopify practice): a version-guard test (`Gem.loaded_specs["actionmcp"].version` against a `Gem::Requirement` with a failure message telling the upgrader what to re-verify) + **`.parameters` pins on every patched method** (`assert_equal [[:req, :request_id], ...], ActionMCP::Server::Tools.instance_method(:send_tools_call).parameters` — catches kwarg renames that arity misses) + one behavioral round-trip test per patched endpoint (the existing `test/initializers/action_mcp_dynamic_tools_test.rb` is that layer). The `sane_patch` gem is the boot-time variant. This directly addresses the loose-pin incident class found in Stage 0.

**Query-count assertions are public API since Rails 7.2** (`ActiveRecord::Assertions::QueryAssertions`, auto-included in every `ActiveSupport::TestCase`): `assert_queries_count(1) { ctx.connected_providers }` pins the one-batched-query contract; `assert_queries_match(/FROM "integrations"/, count: 1)` guards against reintroducing per-tool lookups; `assert_no_queries { tool.available?(ctx) }` after the batch proves memoization. The CurrentAttributes-free `Tools::Context` PORO needs no reset hooks in tests — construct it inline per test.

### Observability and Audit (verified conventions)

**OpenTelemetry MCP semantic conventions exist** (status: Development; moved to `open-telemetry/semantic-conventions-genai`, `docs/gen-ai/mcp.md`) and are the target: span name `{mcp.method.name} {tool}` (e.g. `tools/call slack_post_message`), required `mcp.method.name`, recommended `mcp.session.id` / `mcp.protocol.version` / `gen_ai.tool.name`; histograms `mcp.server.operation.duration`; and a codified error taxonomy — JSON-RPC error code string vs **`error.type = "tool_error"` when `isError: true`** — giving the protocol-vs-execution split as one low-cardinality dimension. Tool-name metric labels are safe at ~52 fixed names; map unknown client-supplied names to `_unknown_` to guard cardinality. Key production signals: per-tool latency/error-rate histograms, and **`tools/list` count per session** — a drop after deploy is the registry-regression alarm.

**Audit log field consensus** (converging across vendor/security sources; no single standard): timestamp, tool name, provenance (handler class + registry version / shadow-row id), args **hashed by default** with a per-tool allowlist of loggable args declared in the `tool` DSL, session + company + principal, client name/version from `initialize`, duration, outcome (`ok`/`tool_error`/`protocol_error`/`timeout`/`denied`). Never log integration credentials; redact before storage. Retention: hot 30–90 days, cold archive; sample routine successes, always log mutating/high-risk tools at 100%.

### Rollout and Cutover

**Official conformance tooling is CI-ready:** `modelcontextprotocol/conformance` (v0.1.16, actively maintained) runs against a live URL with `--suite` / `--spec-version` filters, an `--expected-failures` baseline, and a GitHub Action — run it against both mounts as a gate during any serving-path change (especially the Stage-4 gem decision). MCP Inspector for manual verification.

**Client reality constrains the cutover:** agent CLIs cache the tool list per session and unreliably honor `list_changed`, so **tool names and input schemas must stay byte-stable across the migration** (the parity gate is also a client-compatibility gate). Rollout mechanics: dual-mount alias route (agent CLIs are URL-configured — a canary cohort is "point `.mcp.json` at the new URL"), then per-tenant Flipper flag with percentage-of-actors for gradual cutover; smoke-test real CLIs (Claude Code + Cursor: `tools/list` count + one `tools/call` per critical tool) before deleting legacy paths.

**Boot-reconciler production guards** (Solid Queue's own README warns about unlocked boot-time reconciliation; K8s rollouts amplify the herd): `pg_try_advisory_xact_lock` and **skip, don't wait** (one pod reconciles, N−1 no-op); skip when migrations are pending (`check_all_pending!` rescue); `lock_timeout`/`statement_timeout` on the reconciler connection; **fail-open** — rescue, log, serve from existing rows rather than crash-loop a deploy; and make boot **check-then-heal** (cheap read-only drift check first, lock + upsert only on mismatch) so steady-state boots are write-free.

**Drift-check surfacing** (Terraform drift-detection practice mapped onto `tools:check`): distinct exit codes (0 clean / 2 drift / 1 broken) so pipelines distinguish drift from breakage; blocking in CI; cron in prod routed to Slack, not pager; a `tools.drift.count` gauge (labeled missing-row/orphan-row/definition-mismatch) on the MCP traffic dashboard. Page only on runtime symptoms (tool-count drop, unknown-tool protocol errors, call error-rate spikes).

## Technical Research Recommendations

### Implementation Roadmap

Stage 0 (hotfixes + ops hardening) → Stage 1 (registry + shadow rows + parity gate, no serving change) → Stage 2 (availability unification) → Stage 3 (taxonomy cutover behind env flag) → Stage 4 (kind drop; gem decision; policy layer) — as detailed in the Architectural Patterns section. Every stage independently shippable and revertible; the only irreversible door (column drop) ships last, weeks after cutover.

### Technology Stack Recommendations

- **Now:** stay on actionmcp exact-pinned at 0.104.1; all new logic in gem-agnostic `Tools::*` (Registry / Context / Definition / Reconciler).
- **Stage 4 default:** official `mcp` gem (Shopify + MCP org, weekly releases, protocol 2025-11-25, server-per-request stateless idiom) over rewriting the patch against actionmcp 0.111 internals — endorsed by all three judges. Re-verify gem APIs at implementation time (0.22.x was current at research date).
- **Async:** keep `execution_id` + `read_tool_result`; harden per the pitfalls list; revisit MCP tasks only after the 2026-07-28 extension ships and a mainstream client sends task-augmented calls.
- **Quotas:** Postgres dispatch-time slot counter per company + Temporal Task Queue Fairness (`fairness key = company_id`) + worker tuner as the global cap; bounded queue with position feedback, fast structured rejection beyond it.
- **Policy layer:** Flipper (actor = company) AND-ed into availability, preload middleware on.

### Success Metrics

- Zero tool-definition drift incidents (today's class: "wrote the handler, forgot the seed/migration") — measured by `tools:check` staying green in prod.
- Adding a platform tool = one file, one PR, zero migrations (except renames) — measured by diff size of the next 5 tool additions.
- `tools/list` p95 latency unchanged ±10% through Stages 2–3; tool count per session-type stable across each deploy.
- No increase in `tool_error`/protocol-error rates during cutover (OTel dashboards from day one of Stage 2).
- Integration-gated tools invisible without the integration and correctly re-appearing on connect (integration test per provider).

---

## Research Conclusion

The research goals were met in full: a registry design where code-defined platform tools need no pre-created DB rows (shadow rows are machine-owned projections with boot self-heal and lazy materialization — the human sync burden is eliminated); a tagging model of orthogonal axes (`source`, `user_attachable`, closed-vocabulary tags, code-only injection rules and managed-provider metadata) replacing the `kind` enum; a single availability predicate evaluated at list/call/picker time from one batched query, unifying the three existing gating mechanisms; and a staged, FK-safe migration path with byte-parity and kill-switch guarantees at each stage.

Methodology: codebase audit (Explore agent), four parallel research workflows (18 web researchers + 2 completeness critics, all load-bearing claims verified against primary sources), and a three-architect/three-judge design panel with code-verified scoring. Full design documents and judge scorecards: `ai/research/technical-aixle-mcp-tool-registry-appendix-2026-07-02/`.

**Research Completion Date:** 2026-07-02
**Source Verification:** all key claims cited against primary sources current as of the research date; confidence levels noted inline where sources were weaker.

_Next step: implementation per the staged roadmap (Stage 0 first — the Builder hotfix and gem pin are urgent regardless of the redesign)._
