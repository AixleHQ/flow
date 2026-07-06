KEY DECISIONS:
- Platform tools become single Ruby classes (schema + metadata + availability + behavior) in app/tools/platform_tools/, discovered via eager_load_namespace + descendants snapshotted into a frozen index in to_prepare — immune to both dev-reload wipes and Puma write races; actionmcp's global ToolsRegistry is never used
- Keep definition-free, write-locked 'anchor' rows for platform tools (Solid Queue mirror pattern), reconciled from the registry by an advisory-locked deploy task — FKs (tool_results, session_tools) and JSONB tool_ids in workflow configs keep working with zero data migration; serving never reads them
- Anti-shadowing is structural: call resolution order is managed-namespace → platform registry → DB custom, plus a DB CHECK banning mcp__* names and publisher-enforced reserved prefixes — a custom row physically cannot answer a platform or managed name
- One tri-state availability predicate availability(ctx) -> :ok | :unavailable | :forbidden evaluated per-request at tools/list (hide), tools/call (enforce: actionable isError vs opaque unknown-tool to avoid entitlement leaks), and UI pickers — replacing requires_integration SQL, ManagedMCPToolRegistry, and in-handler gates; fed by one batched IntegrationSet query on an explicitly threaded frozen ToolContext (no CurrentAttributes)
- kind enum replaced by orthogonal axes: closed category vocabulary, exposure (agent/picker/builder/managed_only), a closed named inject_into rule set reproducing available_tools auto-injection, integration requirement, and MCP risk annotations; source(platform/custom) is a structural column, not a tag
- Custom tools write only through CustomTools::Publisher: spec-regex + reserved-name rejection, JSON-Schema 2020-12 meta-validation with $ref rejection, text sanitization, digest-pinned docker images, and a publisher-set definition_digest that list/call re-verify — DB rug pulls fail closed and alert
- Swap actionmcp for the official mcp gem with server-per-request stateless StreamableHTTP in a plain Rails controller (Fleetio pattern), deleting the monkey-patch; mcp__<server>__ Coder namespacing and execution_id+read_tool_result polling preserved; list_changed push knowingly sacrificed since per-request lists are authoritative
- tool_results gains tool_key/tool_source strings (backfilled) and tool_id goes nullable — provenance survives row churn and anchors can be retired later without schema changes
- Six independently shippable stages, each with an explicit rollback; reconciler's write-definitions mode keeps the legacy DB-serving path as a rollback target until the new path has baked a full release
- Ops hardening rides along as Stage 0: Slack tokens_revoked/app_uninstalled consumers, Temporal heartbeats + docker-kill-on-cancel, read_tool_result truncation/paging (~10k token cap), tool_invocations audit log, and a tools:drift CI/scheduled task

RISKS:
- Stage 4 transport swap is the riskiest step: four agent CLIs (claude_code, cursor_cli, codex, gemini_cli) must be canaried against the official gem's protocol-version and response-shape differences; mitigated by dual-mount + per-company URL flag, but a subtle client incompatibility could stall the actionmcp removal
- Anchor-row reconciler runs at deploy, not boot — a brand-new platform tool is listable/callable immediately but not id-attachable (pickers/meta_create_step) until the rake task runs; a forgotten task run is caught only by the drift check
- Grandfathered bare custom-tool names can collide with future platform keys; resolution order prevents shadowing but the tenant's tool silently loses list precedence until the drift task flags it and a human renames it
- definition_digest fails closed: any legitimate write path that forgets to go through CustomTools::Publisher (new admin UI, console fix-up) makes the tool vanish from lists in production — safe but a support-ticket generator; needs loud alerting and a documented re-publish command
- Losing list_changed push in stateless mode means clients with frozen lists (Cursor) only learn about integration connects/disconnects via call-time errors until they re-list — degraded UX accepted by design but visible to users
- Folding 52 handlers + seeds + InternalToolStrategy.define blocks into classes is a large mechanical migration; a transcription error in a schema changes agent-visible behavior — the Stage 1 drift-parity gate (registry vs seeded rows) is the only automated defense and must diff full wire definitions, not just names
- The official mcp gem is a new dependency with its own churn (Shopify+MCP org); server-per-request construction adds per-request allocation cost that should be benchmarked on hot MCP paths
- The 2026-07-28 MCP revision lands mid-migration; the design aligns with its stateless/per-request-auth direction, but deterministic ordering, ttlMs caching metadata, and the tasks extension may require follow-up work not scheduled here

# Aixle Code-First MCP Tool Registry — Architecture Design (Design C: risk-first)

**Scope:** platform tools defined and served from code with no hand-maintained DB definitions; DB reserved for user-authored custom tools; a tag/exposure taxonomy replacing the `kind` enum; one availability predicate replacing three gating mechanisms; a staged, FK-safe migration.

**Design stance.** Every choice below is derived from the threat model and failure modes in the research doc: tool poisoning via user-authored metadata, intra-list shadowing, DB rug-pulls, name collision, non-thread-safe global registries, dev-reload registry wipes, stale integration rows after Slack uninstall, Temporal cancels that never reach the container, and 10k-token result blowups. Where a purist design ("no rows at all") conflicts with FK/data safety, FK safety wins and the residual risk is neutralized structurally instead (definition-free anchor rows that cannot be served from).

---

## 0. Trust boundaries (the frame everything hangs on)

```
┌─ TRUSTED ────────────────────────────────────────────────┐
│ PlatformTools::* classes (code, reviewed, deployed)      │
│ PlatformTools::Registry (frozen, rebuilt per reload)     │
│ Anchor rows in `tools` (id-stable, definition-free,      │
│   written ONLY by the reconciler)                        │
└──────────────────────────────────────────────────────────┘
┌─ UNTRUSTED (tenant-authored) ────────────────────────────┐
│ Custom `tools` rows: name/description/input_schema/      │
│   command/docker_image + tool_files                      │
│ Written ONLY through CustomTools::Publisher (validation  │
│   pipeline + definition_digest pinning + audit log)      │
└──────────────────────────────────────────────────────────┘
```

Invariants made structural, not procedural:

1. **A DB row can never shadow a platform tool.** Call-time resolution order is managed-namespace → platform registry → DB, in that order, always. Even a validation bypass (console `update!`) cannot make a custom row answer a platform name.
2. **A platform definition can never be served from the DB.** Anchor rows have `description = NULL`, `input_schema = '{}'` (end state); the serving path reads only registry classes. There is nothing to poison.
3. **Custom rows that were not written by the sanctioned publisher do not serve.** `definition_digest` is set only by the publisher; the list/call path recomputes and fails closed on mismatch (rug-pull defense).
4. **`mcp__` is a reserved wire namespace** enforced by a DB CHECK constraint — the DB emit path physically cannot produce a managed-server-shaped name.

---

## 1. Registry design

### 1.1 Where classes live

`app/tools/platform_tools/*.rb` → `PlatformTools::SlackPostMessage`, `PlatformTools::BoardAddComment`, … (Zeitwerk default mapping for `app/tools`, no autoloader config needed). The 52 `InternalTools::*` handlers are moved here and merged with their seed metadata — **one class = schema + metadata + availability + behavior**, killing the `db/seeds/platform_tools.rb` ↔ handler duplication (the "wrote the class, forgot the seed" drift class of bugs disappears by construction: the class *is* the seed).

`app/mcp/tools/` (actionmcp's directory) stays empty and is deleted in the final stage together with the gem (§5).

### 1.2 Base class + DSL (concrete)

```ruby
# app/tools/platform_tools/base.rb
module PlatformTools
  class Base
    Outcome = Struct.new(:exit_code, :stdout, :stderr, keyword_init: true)

    CATEGORIES = %i[boards messaging workflow_control session_lifecycle
                    builder compute execution_support source_control].freeze
    EXPOSURES  = %i[agent picker builder managed_only].freeze

    class << self
      attr_reader :integration_requirement, :managed_provider_name

      def abstract! = @abstract = true
      def abstract? = @abstract == true

      # -- identity ------------------------------------------------------
      def key(value = nil)
        @key = value.to_s if value
        @key ||= name.demodulize.underscore   # SlackPostMessage -> "slack_post_message"
      end

      def display_name(v = nil) = v ? @display_name = v : (@display_name ||= key.titleize)
      def description(v = nil)  = v ? @description = v  : @description

      # -- taxonomy (§2) ---------------------------------------------------
      def category(v = nil)
        if v
          raise ArgumentError, "unknown category #{v}" unless CATEGORIES.include?(v)
          @category = v
        end
        @category
      end

      def exposure(*vals)
        return @exposure ||= [:agent] if vals.empty?
        bad = vals - EXPOSURES and raise ArgumentError, bad.inspect if (vals - EXPOSURES).any?
        @exposure = vals.freeze
      end

      def inject_into(*rule_names)  # closed set, see §2.3
        return @inject_into ||= [] if rule_names.empty?
        rule_names.each { |r| InjectionRules.validate!(r) }
        @inject_into = rule_names.freeze
      end

      # -- gating (§3) -----------------------------------------------------
      def requires_integration(provider = nil)
        @integration_requirement = provider&.to_sym || @integration_requirement
      end

      def managed_provider(provider) = @managed_provider_name = provider.to_sym

      def feature_flag(flag = nil) = flag ? @feature_flag = flag : @feature_flag

      # -- MCP annotations (risk axis, wire-visible) ------------------------
      def annotations(read_only: nil, destructive: nil, idempotent: nil, open_world: nil)
        @annotations = { readOnlyHint: read_only, destructiveHint: destructive,
                         idempotentHint: idempotent, openWorldHint: open_world }.compact.freeze
      end
      def annotation_hints = @annotations || {}

      # -- schema ------------------------------------------------------------
      def property(name, type:, description: nil, required: false, **opts)
        (@properties ||= {})[name.to_s] =
          { type: type.to_s, description: description, **opts }.compact
        (@required ||= []) << name.to_s if required
      end

      def input_schema(literal = nil)
        return @input_schema = literal.deep_stringify_keys if literal
        @input_schema ||= {
          "type" => "object",
          "properties" => (@properties || {}).deep_stringify_keys,
          "required" => (@required || []),
          "additionalProperties" => false
        }
      end

      # -- execution ---------------------------------------------------------
      def execution(mode = nil) = mode ? @execution = mode : (@execution ||= :app)

      # -- availability (§3): tri-state, overridable ---------------------------
      # :ok          -> list + serve
      # :unavailable -> entitled but capability missing (hide; actionable error on call)
      # :forbidden   -> outside entitlement (hide; opaque unknown-tool on call)
      def availability(ctx)
        return :forbidden unless exposure_permits?(ctx)
        return :unavailable if feature_flag && !ctx.flag_enabled?(feature_flag)
        if integration_requirement && !ctx.integrations.active?(integration_requirement)
          return :unavailable
        end
        :ok
      end

      def exposure_permits?(ctx)
        return true  if exposure.include?(:agent)
        return ctx.builder_session?      if exposure.include?(:builder)
        return ctx.managed_dispatch?     if exposure.include?(:managed_only)
        false
      end

      # -- hash pin for drift/audit -------------------------------------------
      def definition_digest
        @definition_digest ||= Digest::SHA256.hexdigest(
          JSON.generate({ key: key, description: description,
                          input_schema: input_schema, annotations: annotation_hints,
                          category: category, exposure: exposure.sort }.sort.to_h)
        )
      end
    end

    attr_reader :ctx, :params, :mcp_server

    def initialize(ctx:, params:, mcp_server: nil)
      @ctx = ctx
      @params = (params || {}).with_indifferent_access
      @mcp_server = mcp_server
    end

    def call = raise NotImplementedError

    private

    def session   = ctx.session
    def project   = ctx.project
    def step_run  = ctx.session&.step_run

    def require_workflow_context!
      raise WorkflowContextError, "requires a workflow context" unless step_run
    end

    def success(text) = Outcome.new(exit_code: 0, stdout: text.to_s, stderr: "")
    def error(text)   = Outcome.new(exit_code: 1, stdout: "", stderr: text.to_s)
  end
end
```

Example — the Slack handler, seed metadata folded in, in-handler gate demoted to call-time *enforcement* of the same declaration:

```ruby
# app/tools/platform_tools/slack_post_message.rb
module PlatformTools
  class SlackPostMessage < Base
    display_name "Slack: Post Message"
    description  "Send a Slack message from the workflow. Text and files are both " \
                 "optional but at least one is required..."
    category  :messaging
    exposure  :agent, :picker
    requires_integration :slack
    annotations read_only: false, idempotent: false, open_world: true

    property :text,      type: :string, description: "Message text (optional if files given)"
    property :channel,   type: :string, description: "Channel; defaults to triggering message"
    property :thread_ts, type: :string
    property :files,     type: :array,
             items: { type: "object",
                      properties: { filename: { type: "string" }, content: { type: "string" },
                                    title: { type: "string" } } }

    def call
      require_workflow_context!
      # availability was checked at list AND call boundary; this re-resolves the
      # concrete Integration row (enforce, don't trust the earlier check):
      integration = resolve_slack_integration or
        return error("Slack is not connected for this project — connect it in Settings → Integrations")
      ...
    end
  end
end
```

Container-mode platform tool (unifies `InternalToolStrategy.define` metadata into the same class):

```ruby
module PlatformTools
  class RepoIndex < Base
    category :compute
    exposure :agent, :picker
    execution :container
    container image: "aixle/repo-index:1", timeout: 600, memory: 2.gigabytes  # thin wrapper over InternalToolStrategy::Definition
    property :repository_id, type: :integer, required: true
    ...
  end
end
```

### 1.3 Discovery — Zeitwerk pattern chosen and why

**Chosen pattern: `eager_load_namespace` + `descendants`, snapshotted into a frozen index inside `to_prepare`** — a combination of the maintenance_tasks discovery idiom and the Flipper "rebuild every boot/reload" idiom from the research. Rationale against the alternatives:

- actionmcp's own `ToolsRegistry` (load-hook registration into a global mutable Hash) is rejected: it is **non-thread-safe** and wiped by the engine's `to_prepare` `clear!` — both documented failure modes. We do not touch it at all.
- `safe_constantize`-at-call-time (string names) is reload-proof but gives no *enumeration* without a manifest — recreating the drift problem one layer up.
- A boot-only initializer registry holds stale class objects after the first dev reload — explicitly forbidden by the Rails autoloading guide.

The frozen-snapshot-in-`to_prepare` shape is immune to both hazards: it never survives a reload (no stale classes), and after the atomic ivar swap it is **immutable**, so Puma threads only ever read a frozen Hash (no write races, unlike actionmcp's registry).

```ruby
# app/tools/platform_tools/registry.rb
module PlatformTools
  class Registry
    class DuplicateKeyError < StandardError; end

    class << self
      def index = @index || rebuild!
      def all   = index.values
      def fetch(key) = index[key.to_s]
      def key?(key)  = index.key?(key.to_s)

      # Reserved names the custom-tool publisher must reject (§0 inv. 4, §2.4).
      def reserved?(name)
        n = name.to_s
        key?(n) || n.start_with?("mcp__") || RESERVED_PREFIXES.any? { |p| n.start_with?(p) }
      end
      RESERVED_PREFIXES = %w[board_ coder_ meta_ slack_ aixle_].freeze

      def rebuild!
        Rails.autoloaders.main.eager_load_namespace(PlatformTools) unless Rails.application.config.eager_load
        classes = PlatformTools::Base.descendants.reject(&:abstract?)
        idx = {}
        classes.each do |klass|
          raise DuplicateKeyError, klass.key if idx.key?(klass.key)
          idx[klass.key] = klass
        end
        @index = idx.freeze   # atomic swap; readers see old or new, never partial
      end
    end
  end
end

# config/initializers/platform_tools_registry.rb
Rails.application.config.to_prepare do  # idempotent: runs at boot and on every dev reload
  PlatformTools::Registry.rebuild!
end
```

### 1.4 Unification with DB custom tools: `ToolCatalog`

One service is the *only* producer of tool lists for all three consumers (MCP `tools/list`, MCP `tools/call` resolution, UI pickers). Both sides are mapped into one duck-typed `Entry` (the GoodJob `CronEntry`-beside-rows pattern from the research):

```ruby
# app/services/tool_catalog.rb
class ToolCatalog
  Entry = Data.define(:wire_name, :key, :display_name, :description, :input_schema,
                      :annotations, :meta, :source,       # :platform | :custom | :managed
                      :availability,                       # :ok | :unavailable (pre-evaluated)
                      :executor)                           # PlatformExecutor | CustomExecutor

  def self.for_session(session)
    ctx = ToolContext.for_session(session)          # §3 — ONE batched integration query
    entries = []
    entries += platform_entries(ctx)                # attached anchors + injection rules
    entries += custom_entries(ctx)                  # DB rows, digest-verified
    entries += managed_entries(ctx)                 # mcp__<server>__<key> namespaced
    dedupe_platform_wins(entries).sort_by(&:wire_name)   # deterministic order (2026-07-28 RC)
  end

  def self.picker_entries(project:)                 # replaces Tool.visible_for_project
    ctx = ToolContext.for_project(project)
    platform = PlatformTools::Registry.all
      .select { |k| k.exposure.include?(:picker) && k.availability(ctx) == :ok }
      .map    { |k| picker_entry(k, ctx) }          # carries anchor row id for attachment
    custom = Tool.custom_source.not_deleted.enabled.scoped_to(project)
      .select { |t| CustomTools::Verifier.digest_ok?(t) }
      .map    { |t| picker_entry(t, ctx) }
    platform + custom
  end

  # Resolution for tools/call — ORDER IS THE ANTI-SHADOWING GUARANTEE (§0 inv. 1)
  def self.resolve(session, wire_name)
    ctx = ToolContext.for_session(session)
    if (server_name, base = ManagedNamespace.parse(wire_name))
      return resolve_managed(ctx, server_name, base)          # 1. managed namespace
    end
    if (klass = PlatformTools::Registry.fetch(wire_name))
      return Resolution.platform(klass, klass.availability(ctx)) # 2. platform registry
    end
    resolve_custom(ctx, wire_name)                              # 3. DB custom rows
  end
end
```

`dedupe_platform_wins` drops (and `Rails.error.report`s) any custom entry whose wire name equals a platform key — defense in depth on the list path; the publisher should have made this impossible at write time.

`custom_entries` verifies `definition_digest` per row before emitting (§4.2); mismatch → excluded + alert, never served.

---

## 2. Tagging taxonomy

Three orthogonal axes (the cross-platform consensus from the research: Dify's closed category vocabulary; provider grouping via *namespacing*, not tags; MCP annotations as the risk axis) plus two Aixle-specific structural axes. **Every axis is load-bearing** — it drives filtering, gating, or dispatch (the LangChain lesson: tags that do nothing rot).

| Axis | Values | Drives |
|---|---|---|
| `category` (closed vocab) | `boards, messaging, workflow_control, session_lifecycle, builder, compute, execution_support, source_control` | picker grouping, `_meta` tags on the wire |
| `exposure` | `agent` (listed to sessions), `picker` (attachable in UI), `builder` (Aixle Builder sessions only), `managed_only` (served solely under a managed-server namespace) | who can see/attach/call |
| `inject_into` | closed rule set (§2.3) | auto-injection, replacing kind-driven queries |
| integration axis | `requires_integration :slack` etc. + name prefix convention (`slack_`, `board_`, `coder_`) | availability predicate + agent-side grouping |
| risk axis | MCP `annotations` (`read_only/destructive/idempotent/open_world`) | client confirmation policies; future per-tenant policy ("no destructive tools in non_interactive mode") |

`source` (`platform` vs `custom`) is **not** a tag — it is a structural column/fact (which side of the trust boundary the definition lives on).

On the wire, category + provider ship via the sanctioned `_meta` extension point: `"_meta": { "ai.aixle/tags": ["messaging", "slack"], "ai.aixle/source": "platform" }`.

### 2.1 Mapping the five current kinds

| Old `kind` | New expression |
|---|---|
| `custom` | `source: :custom` DB row (structural, not taxonomy) |
| `system` (board_*, coder_*) | `exposure :agent, :picker` (board_*) / `exposure :managed_only` + `managed_provider :coder` (coder_*); `category :boards` / `:compute` |
| `internal` (read_tool_result) | `exposure :agent` *not* `:picker`; `inject_into :sessions_with_container_tools`; `category :execution_support` |
| `internal` (finish/fail_session) | `inject_into :non_interactive_sessions`; `category :session_lifecycle` |
| `workflow` (list_sub_steps, mark_sub_step) | `inject_into :workflow_step_sessions`; `category :workflow_control` |
| `meta` (meta_*) | `exposure :builder`; `category :builder` — excluded from pickers exactly as today, and now *also* gated at list/call time on `ctx.builder_session?` (defense-in-depth the kind enum never gave: mis-attaching a meta tool to a normal session no longer exposes it) |

Note one deliberate behavior fix: today's `visible_for_project` scope leaks `internal`/`workflow` kinds into the picker query; the new `exposure :picker` whitelist makes picker visibility an explicit per-tool decision, reviewed tool-by-tool during the class migration.

### 2.2–2.3 Auto-injection rules — closed, named, auditable

Arbitrary lambdas on tool classes are rejected (unauditable, and the availability logic would be scattered again). Injection conditions form a **closed named set** defined in one file; tool classes may only reference names:

```ruby
# app/tools/platform_tools/injection_rules.rb
module PlatformTools
  module InjectionRules
    RULES = {
      workflow_step_sessions:        ->(ctx) { ctx.session_type == "workflow_step" },
      sessions_with_container_tools: ->(ctx) { ctx.container_tools_present? },
      non_interactive_sessions:      ->(ctx) { ctx.mode == "non_interactive" }
    }.freeze

    def self.validate!(name) = RULES.key?(name) || raise(ArgumentError, "unknown injection rule #{name}")
    def self.applies?(name, ctx) = RULES.fetch(name).call(ctx)
  end
end
```

`ToolCatalog.platform_entries(ctx)` = (anchors attached via `session_tools`, resolved to registry classes by name) ∪ (registry classes with any matching `inject_into` rule), each then filtered by `availability(ctx) == :ok`. `ctx.container_tools_present?` is computed over the already-assembled attached+custom set exactly as `available_tools` does today, so `read_tool_result` keeps appearing precisely when a container tool is in play.

This reproduces `TerminalSession#available_tools` line-for-line, but each rule is a named, greppable, individually testable declaration instead of four interleaved DB queries keyed on an enum.

---

## 3. Availability predicate

### 3.1 Signature and context

Tri-state (not boolean) because the research's entitlement-leak finding requires distinguishing two "not available" flavors at the call boundary:

```ruby
klass.availability(ctx) -> :ok | :unavailable | :forbidden
```

- `:ok` — listed and callable.
- `:unavailable` — entitled but capability missing (Slack not connected, feature flag off). Hidden at list time; **called anyway** (stale client list) → `isError: true` tool result: `"Slack is not connected for this project — connect it at Settings → Integrations → Slack"` (per SEP-1303: execution error, so the model can self-correct / relay the remedy).
- `:forbidden` — outside the entitlement boundary (meta tool in a non-builder session, cross-tenant custom tool, managed-only tool called bare). Hidden at list time; called → plain protocol `method_not_found` "Tool 'x' not available" — the remedy message must not leak capability existence across the boundary.

The context object — an explicit, frozen, per-request value. **Explicit threading is chosen over `CurrentAttributes`**: the thoughtbot leak incident plus the fact that our two non-Rack execution surfaces (SSE streams, Temporal activity threads) don't get executor resets make ambient state a footgun here.

```ruby
# app/services/tool_context.rb
class ToolContext
  attr_reader :session, :project, :company, :integrations, :flags,
              :session_type, :mode

  def self.for_session(session)
    new(session:, project: session.project, company: session.project&.company || session.user.company)
  end
  def self.for_project(project) = new(project:, company: project.company)

  def initialize(session: nil, project:, company:)
    @session, @project, @company = session, project, company
    @integrations = IntegrationSet.load(project:, company:)   # ONE query, see below
    @flags = Flipper.preload_all_for(company)                  # policy layer, optional
    @session_type = session&.session_type
    @mode = session&.mode
    freeze
  end

  def builder_session?  = session&.session_config&.dig("aixle_builder") == true
  def flag_enabled?(f)  = @flags.enabled?(f)
  def container_tools_present? = ... # set by catalog during assembly (see §2.3)
end

# app/services/integration_set.rb — the batched loader
class IntegrationSet
  def self.load(project:, company:)
    rows =
      if project
        Integration.active
          .where("(project_id = :pid) OR (project_id IS NULL AND company_id = :cid)",
                 pid: project.id, cid: company.id).pluck(:provider, :id, :project_id)
      elsif company
        Integration.active.company_wide.where(company_id: company.id).pluck(:provider, :id, :project_id)
      else
        []
      end
    new(rows)
  end

  def initialize(rows)
    @providers = rows.map { |p, _, _| p.to_sym }.to_set.freeze
    @ids_by_provider = rows.group_by { |p, _, _| p.to_sym }
                           .transform_values { |v| v.map { |_, id, _| id } }.freeze
  end

  def active?(provider) = @providers.include?(provider.to_sym)
  def ids_for(provider) = @ids_by_provider.fetch(provider.to_sym, [])
end
```

Exactly one `Integration` query per MCP request / picker render, evaluated against every tool's predicate in memory — never a query per tool (Flipper-preload shape from the research).

### 3.2 Where it is evaluated — and how this unifies the three mechanisms

| Surface | Behavior |
|---|---|
| `tools/list` | filter: only `:ok` entries emitted. Recomputed **every request** from current DB state (the spec-blessed per-request-auth pattern; also the only mechanism that works across Claude Code/Cursor/connector given broken `list_changed` support) |
| `tools/call` | enforce: re-resolve + re-evaluate before dispatch; `:unavailable` → actionable `isError`, `:forbidden` → protocol error. Hiding is never authorization |
| UI pickers | same predicate via `ToolCatalog.picker_entries(project:)` — deletes the `requires_integration IN (?)` SQL fork and its scope-vs-runtime divergence |
| handler body | *enforcement remains* (resolve the concrete Integration row, fail with the same actionable message) — belt and suspenders, since handlers can be invoked from non-MCP paths |

The three legacy mechanisms collapse into one declaration + one evaluator:
1. `tools.requires_integration` column → platform: class declaration; custom rows: column kept, read by `CustomEntry#availability`.
2. `Integrations::ManagedMCPToolRegistry` → deleted; replaced by `managed_provider :coder` + `exposure :managed_only` class metadata (the managed list for a server = registry classes whose `managed_provider` matches `server.integration.provider`).
3. In-handler checks → demoted from *gate* to *enforcement* of the same declared fact.

### 3.3 Eventing (keeping the DB truthful + best-effort push)

- `Integration` `after_commit on: [:update, :destroy]` (status/deleted change) → `ToolListChangedJob` → best-effort `notifications/tools/list_changed` to live sessions where transport allows; never load-bearing (per-request recompute is authoritative).
- **New (gap found by the audit): Slack `tokens_revoked` + `app_uninstalled` event consumers** flip the Integration row to `error`/`inactive`; without this the predicate serves dead Slack tools indefinitely. Handle out-of-order delivery (either event alone must deactivate).
- Coder: scheduled health-check poll (self-hosted → no webhook); failure flips status to `error`.

---

## 4. DB / FK strategy

### 4.1 The binding constraints (verified in schema + code)

- `tool_results.tool_id` is `null: false` + FK to `tools`.
- `session_tools.tool_id` FK (cascade) — populated by `SessionService` from step/workflow config.
- **Workflow and step configs store integer `tool_ids` in JSONB** (`workflow.config["base_tool_ids"]`, step `config[:tool_ids]` via meta_create_step) — a hard dependency on *id-stable rows existing for attachable platform tools*.

That last fact decides the fork: pure "no rows" would require migrating opaque JSONB configs across all tenants — the riskiest possible data migration. **Chosen strategy: Solid Queue's mirror-row pattern — definition-free "anchor" rows, owned exclusively by a reconciler, kept permanently.** Rows exist to satisfy FKs and id-based attachment; they are *never* the source of any definition. The rug-pull/poisoning surface of platform rows is removed by making them definition-free and write-locked, not by deleting them.

### 4.2 `tools` table changes

```ruby
add_column :tools, :source, :string, null: false, default: "custom"   # 'platform' | 'custom'
add_column :tools, :definition_digest, :string                        # custom rows: publisher-pinned hash
add_column :tools, :docker_image_digest, :string                      # custom rows: sha256 image pin
add_index  :tools, :source
add_check_constraint :tools, "name NOT LIKE 'mcp\\_\\_%'", name: "tools_name_no_managed_ns"
# later stage: drop kind, drop requires_integration for platform rows only (column stays for custom)
```

**Anchor rows (source='platform'):** `name` (= registry key), `display_name`, `execution_mode`, `enabled`, `source`. `description = NULL`, `input_schema = {}` (end state), `scope` NULL. Write-locked:

```ruby
# app/models/tool.rb
def readonly?
  return false if PlatformTools::Reconciler.reconciling?  # thread-local flag
  super || source == "platform"
end
```

**Reconciler** (replaces `Seeds::PlatformTools.seed!` and the `MigrationTool` data-migration pattern — the class is now the seed):

```ruby
module PlatformTools
  class Reconciler
    def self.sync!
      Tool.with_advisory_lock("platform-tools-reconcile") do   # boot storms / multi-node deploys
        reconciling do
          keys = Registry.index.keys
          Registry.all.each do |klass|
            row = Tool.where(source: "platform", name: klass.key).first_or_initialize
            row.assign_attributes(
              display_name: klass.display_name, execution_mode: klass.execution.to_s,
              enabled: true, deleted_at: nil, kind: legacy_kind(klass), # kept until kind is dropped
              description: nil, input_schema: {}                        # definition-free (Stage 5)
            )
            row.save!
          end
          Tool.where(source: "platform").where.not(name: keys).update_all(enabled: false) # disable, never delete (FKs)
        end
      end
    end
  end
end
```

Runs from the deploy rake task (`platform_tools:reconcile`, replacing `platform_tools:seed`). Deliberately **not** in `to_prepare`: DB writes at boot race migrations, read replicas, and multi-process boot storms. A missing/stale anchor is not fatal to serving (the catalog serves from code); it only blocks id-based attachment of a brand-new tool until the deploy task runs — acceptable and self-healing.

**Custom rows:** all writes funnel through `CustomTools::Publisher` (used by the UI controllers *and* `meta_create_tool`):

- validation pipeline (creation-time, expensive once): spec name regex (`[a-z][a-z0-9_]*`, ≤128), `Registry.reserved?` rejection (platform keys, `RESERVED_PREFIXES`, `mcp__`), JSON-Schema 2020-12 meta-validation, reject `$ref`/`$defs`/`$dynamicRef` (one bad `$ref` can break a client's whole tool list), size/depth/property caps, `additionalProperties: false` required, free-text sanitization of *all* strings incl. nested schema descriptions (strip `<IMPORTANT>`-style tags, flag imperative-injection patterns) — the TPA checklist from the research;
- resolves `docker_image` → digest, stores `docker_image_digest`; `CustomToolStrategy#resolve_image` runs `image@sha256:…` when present (rug-pull-proof images);
- computes and stores `definition_digest` over `(name, description, input_schema, command, docker_image_digest, tool_files digest)`. **No model callback recomputes it** — that is the point: any write that bypasses the publisher (console, stray code path, SQL) leaves a stale digest, and the list/call verifier fails closed and alerts. DB-side rug pulls become detectable-by-default.

### 4.3 `session_tools` — no change

Anchors keep every FK valid; `SessionService` keeps attaching by id. (Injection-driven tools stop being represented in `session_tools` at all — they were never inserted there anyway; `available_tools` computed them.)

### 4.4 `tool_results`

```ruby
add_column :tool_results, :tool_key, :string          # provenance that survives row churn
add_column :tool_results, :tool_source, :string       # 'platform' | 'custom' at call time
add_index  :tool_results, :tool_key
# backfill: UPDATE tool_results SET tool_key = tools.name, tool_source = tools.source FROM tools ...
change_column_null :tool_results, :tool_id, true      # after backfill; FK kept for custom rows
```

New writes set `tool_id` (when a row exists — always, given anchors) *and* `tool_key`/`tool_source`. `tool_id` going nullable is the safety valve that decouples analytics/audit from row existence and keeps the door open to retiring anchors someday without another schema change.

### 4.5 Rollback story

- Reconciler is idempotent and additive; anchors are never deleted → any stage can roll back to the previous serving path.
- During Stages 2–4 the reconciler runs in **write-definitions mode** (fills `description`/`input_schema` on anchors *from the registry classes*): the old DB-serving path stays fully functional as a rollback target while the new path bakes. Definition columns are nulled only in Stage 5, after the new path has been the sole reader for a full release cycle.
- `tool_results` changes are purely additive until the `change_column_null`, which is itself reversible while all writes still set `tool_id`.

---

## 5. MCP serving path

### 5.1 Decision: swap actionmcp for the official `mcp` gem (server-per-request, stateless)

The alternative — upgrading actionmcp 0.104.1 → 0.111.x and rewriting the monkey-patch — is rejected on operational-risk grounds: the patched surface changed materially across 7 versions (5th `task_params` arg → `ArgumentError` on day one; cursor pagination; consent gate; strict-param errors; dev-reloader wrapping — all silently bypassed by our overrides), and the patch would keep diverging on every upgrade. Overriding gem internals wholesale *is* the operational failure mode.

The official gem's documented Rails idiom (controller builds an `MCP::Server` per request with a computed `tools:` array; Fleetio runs exactly our per-user-tool-list shape in production) is precisely what the monkey-patch has been simulating — with **zero gem internals overridden**, no process-global registry (no thread-safety issue, no dev-reload wipe, no cross-tenant bleed by construction), first-class `MCP::Tool.define` for DB-built tools (the one thing actionmcp cannot do), and wider protocol-version support (2024-11-05…2025-11-25, vs actionmcp's dropped 2025-03-26 which would break older pinned clients).

```ruby
# app/controllers/mcp_controller.rb
class McpController < ActionController::API
  before_action :authenticate_terminal_session!   # existing mcp_key auth, now plain Rails

  def handle
    entries = ToolCatalog.for_session(@terminal_session).select { |e| e.availability == :ok }
    server = MCP::Server.new(
      name: "aixle",
      tools: entries.map { |e| ToolAdapter.build(e) },   # MCP::Tool.define per entry
      server_context: { terminal_session: @terminal_session }
    )
    render json: MCP::Server::Transports::StreamableHTTPTransport
                   .new(server, stateless: true).handle_request(request)
  end
end
```

`ToolAdapter.build(entry)` wraps `entry.executor` in `MCP::Tool.define(name:, description:, input_schema:, annotations:) { |args, server_context| ... }`; the block:

1. re-runs `ToolCatalog.resolve` + availability (enforce at call — never trust the list),
2. runs `resolve_repository_params` (ported as-is),
3. dispatches: platform/app → `klass.new(ctx:, params:, mcp_server:).call`; container (platform-container or custom) → create `ToolResult` (with `tool_key`/`tool_source`) → Temporal `start_workflow` → return `execution_id` + explicit poll hint ("Poll with read_tool_result, execution_id tr-…, every ~10s") — the async-UX mitigations from the research;
4. `:unavailable` → `isError: true` remedy text; `:forbidden` → unknown tool;
5. appends a `tool_invocations` audit row (session, company, wire_name, key, source, digest-at-call, args fingerprint, outcome, duration).

`InternalToolExecutor` shrinks to a thin adapter during transition and is deleted once handlers are `PlatformTools::*` (its `name.camelize`-convention resolution — the original drift coupling — disappears).

**What is knowingly given up:** stateless mode has no server-initiated stream, so `notifications/tools/list_changed` push over this transport is lost. Accepted: per-request `tools/list` is the only universally honored mechanism anyway (Claude Code partial, Cursor frozen, Anthropic connector re-imports per request), and §3.3's per-request recomputation is authoritative. The tasks/SEP-2663 story is explicitly *not* built on (moving target; no mainstream host sends task-augmented calls); the `execution_id` + `read_tool_result` polling pattern is retained as the interop-safe choice.

### 5.2 Managed MCP servers / Coder namespacing — preserved

The `mcp__<server-name>__<tool>` wire convention survives unchanged (agents' prompts keep working). At list time, for each `session.mcp_servers.where(kind: "managed", enabled: true)`, the catalog emits registry classes with `managed_provider == server.integration.provider` under the namespaced name; availability additionally requires that specific integration active. At call time `ManagedNamespace.parse` (ported verbatim, including first-`__`-split) resolves the server row, and `exposure :managed_only` guarantees coder_* are *never* callable bare (today they leak into the bare list if attached via session_tools — fixed structurally). The DB CHECK from §4.2 guarantees no custom row can ever occupy the `mcp__` namespace.

### 5.3 Operational hardening riding along

- `read_tool_result` gains `offset`/`tail`/`max_bytes` with a default cap ≈ 10k tokens (Claude Code `MAX_MCP_OUTPUT_TOKENS` warning threshold); truncated responses say how to page. Output sanitization applies to this payload too (container stdout re-enters LLM context).
- Temporal container activity: heartbeat every ~10s + Heartbeat Timeout; on `ActivityCancelled` → `docker kill` the labeled container ("Activities must heartbeat to receive cancellations" — today a cancel flips workflow state while the container keeps running).
- `rake tools:drift` (CI + scheduled in prod, modeled on `db:abort_if_pending_migrations` UX): fails on (a) registry keys ↔ anchor rows mismatch, (b) any custom row colliding with a registry key or reserved prefix, (c) `definition_digest` mismatches, (d) anchor rows with non-null definitions after Stage 5.

---

## 6. Migration outline (each stage independently deployable, each with a rollback)

**Stage 0 — hardening that ships now, orthogonal to the registry.**
`CustomTools::Publisher` + validation pipeline + `definition_digest`/`docker_image_digest` columns (route UI + `meta_create_tool` through it); Slack `tokens_revoked`/`app_uninstalled` consumers; Temporal heartbeats + docker-kill-on-cancel; `read_tool_result` truncation/paging; `tool_invocations` audit table. *Rollback: each is an isolated feature flag / additive migration.*

**Stage 1 — registry exists, proves parity, serves nothing.**
Add `app/tools/platform_tools/` Base/Registry/InjectionRules; port all 52 handlers `InternalTools::X` → `PlatformTools::X`, folding in seed metadata and `InternalToolStrategy.define` blocks (mechanical; old constants aliased). Add `tools.source` + backfill (`kind='custom'` → custom, else platform) + CHECK constraint. Ship `rake tools:drift` comparing registry wire-definitions against seeded rows — **CI-green drift is the gate to Stage 2.** *Rollback: registry is dead code.*

**Stage 2 — reconciler replaces seeds.**
`PlatformTools::Reconciler.sync!` in write-definitions mode replaces `Seeds::PlatformTools.seed!` (delete `db/seeds/platform_tools.rb`; `platform_tools:seed` rake aliases to reconcile). Anchor `readonly?` lock. From here, *writing the class is the seed.* *Rollback: re-add seeds file from git; reconciler output is a superset.*

**Stage 3 — one availability predicate everywhere.**
`ToolContext`/`IntegrationSet`; `ToolCatalog.picker_entries` replaces `Tool.visible_for_project`/`visible_for_company` in controllers; `TerminalSession#available_tools` delegates to `ToolCatalog.for_session` (old actionmcp patch consumes catalog entries via a compatibility shim so behavior changes land *before* the transport swap and are diffable). Delete `ManagedMCPToolRegistry` (metadata now on classes). Integration `after_commit` eventing. *Rollback: scopes retained behind a flag for one release.*

**Stage 4 — transport swap.**
Add official `mcp` gem + `McpController` + `ToolAdapter`; dual-mount at a new path; flip agent container MCP URL per company via feature flag; canary; remove `action_mcp_dynamic_tools.rb` and the actionmcp gem when 100%. *Rollback: flip the URL flag back; old path untouched until deletion.*

**Stage 5 — FK/data end state.**
`tool_results.tool_key`/`tool_source` + backfill; `tool_id` nullable; reconciler switches to definition-free mode (nulls anchor `description`/`input_schema`); drop `tools.kind` and platform-row `requires_integration` reads; drift task now also asserts anchors are definition-free. *Rollback: reconciler write-definitions mode restores columns from code at any time.*

**Stage 6 — policy polish (optional, independent).**
Per-tool `feature_flag` declarations wired to Flipper preload (kill switches / gradual rollout, AND-ed with capability, never conflated); per-tenant rate limits/quotas on `tools/call`; `_meta` tags surfaced in pickers; deferred-loading flag (`defer_loading`) as a distinct axis when tool counts approach ~30+.

---

## Honest trade-offs

- **Anchor rows forever ≠ purist "no DB rows".** Chosen because workflow/step JSONB configs reference integer tool ids; migrating opaque tenant JSON is the riskiest step this design refuses to take. The requirement's *spirit* — no hand-maintained rows, no seed drift, serving never depends on a row — is met; rows are inert FK/attachment anchors owned by code. `tool_results.tool_key` keeps the door open to retiring them later.
- **Gem swap over upgrade-in-place** costs a real transport migration (Stage 4) and loses `list_changed` push in stateless mode; bought: deletion of the whole monkey-patch class of risk, per-request isolation, `MCP::Tool.define` for DB tools. If Stage 4 slips, Stages 0–3 still deliver most of the value on the existing patch.
- **Grandfathered custom names** (pre-dating reserved prefixes) may collide with *future* platform keys. Mitigations: resolution order makes shadowing impossible; drift task flags collisions; the reserved-prefix list constrains new platform keys; a colliding legacy custom tool is renamed with the tenant, not silently.
- **Extra ceremony** (publisher-only writes, digest pinning, tri-state availability, closed injection-rule set) is deliberate: each piece hardens a boundary that the research showed being actively exploited in the wild (TPA, rug pulls, shadowing) or failing operationally (registry wipes, stale integrations, zombie containers).