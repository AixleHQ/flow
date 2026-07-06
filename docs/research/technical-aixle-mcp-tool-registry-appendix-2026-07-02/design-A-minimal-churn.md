KEY DECISIONS:
- Definitions live as a class-level `tool do ... end` DSL directly on the existing InternalTools::* handler classes — writing the handler IS the registration; seeds file is deleted after a row-for-row parity test
- Discovery uses eager_load_namespace + descendants with a to_prepare-reset memo of frozen Definition POROs holding class-name strings (maintenance_tasks pattern) — never class objects, never actionmcp's non-thread-safe ToolsRegistry
- Solid Queue-style shadow rows: tools table keeps every existing FK (tool_results.tool_id, session_tools.tool_id, steps.tool_ids) unchanged; a `source` column (code/db) discriminates reconciler-owned projections from user-authored custom tools
- Reconciler runs at deploy (same platform_tools:seed rake name), self-heals at boot under a pg advisory lock, and Tool.shadow_for lazily materializes a row on first FK need — a new class works with zero manual steps
- Removed platform tools are only ever soft-deleted (tool_results FK is RESTRICT); a new partial unique index on name WHERE source='code' is required because the existing NULL-scope index does not enforce platform-name uniqueness
- kind enum is replaced by three orthogonal axes — source column, user_attachable boolean, closed-vocabulary tags jsonb — plus code-only inject_when rules (workflow_step_session / container_tools_present / non_interactive_session) and managed_mcp_provider metadata
- One availability declaration (`requires_integration :slack` + optional lambda), two evaluation strategies: full available?(ctx) predicate at tools/list (hide) and tools/call (enforce with actionable isError-style message for entitled-but-disconnected, method_not_found otherwise); pickers keep the existing SQL clause over a now reconciler-owned requires_integration column
- Tools::Context batches one Integration query per request, memoized on the ctx object itself (deliberately not CurrentAttributes, per the SSE/Temporal reset hazard)
- actionmcp stays exact-pinned at 0.104.x with the monkey-patch shape; the 0.111 upgrade is an isolated Stage-4 project because all new logic (Registry/Context/Definition) is gem-agnostic
- The reconciler keeps writing the legacy kind column through Stage 3 so every rollback lands on rows the previous release fully understands; kind is dropped only in Stage 4 via ignored_columns

RISKS:
- Apparent latent production bug: aixle_builder_controller.rb:24 queries kind: :workflow for meta_* tools moved to kind: :meta (migration 20260627000002), and SessionService#scoped_resources filters through visible_for_project which excludes :meta — Builder likely attaches zero tools today; must verify and hotfix (Stage 0) before Stage 3 touches this path
- The new partial unique index on name WHERE source='code' can fail to create if prod already has duplicate platform-name rows (current NULL-scope index doesn't enforce uniqueness) — requires a dedup pre-check in the migration
- Boot-time reconcile writes from every web/worker process on deploy — mitigated by advisory xact lock, column-existence guard, and ENV kill switch, but a DB outage at boot must not crash the app (rescue + log required)
- Moving auto-injection from kind scopes to registry inject rules changes available_tools, the highest-traffic serving path — env-flagged legacy fallback for one release is the kill switch, but subtle set differences (e.g. coder tools newly hidden without a Coder integration) will surface in workflow prompts/context builders
- Existing source='db' custom rows may already collide with platform tool names (scope-level uniqueness allows it); duplicate names in one tools/list confuse agents — creation-time validation only protects going forward, tools:check must drive manual cleanup
- Renaming a platform tool via the registry alone soft-deletes the old row and inserts a new one, silently orphaning steps.tool_ids/base_tool_ids references — rename data migrations (MigrationTool pattern) remain mandatory and easy to forget
- Deferring the actionmcp upgrade prolongs a 4-arg send_tools_call override that breaks with ArgumentError on any accidental gem bump — the ~> 0.104.0 pin must be exact and commented
- Parity between old seeds and new definitions is only as good as the Stage 1 fixture test; hand-edited prod rows (drifted from seeds) will be overwritten by the first reconcile — run tools:check in report mode against prod before enabling boot reconcile
- In-handler integration checks kept as defense-in-depth can drift from the declared requires_integration (two expressions of the same fact remain, by design), producing inconsistent error messages if only one is updated

# Aixle Code-First MCP Tool Registry — Design A (Minimal Churn, Maximal Safety)

**Author lens:** evolve the current system in place. Keep actionmcp 0.104.1 and the monkey-patch shape, keep the `tools` table and every existing FK working unchanged via **Solid Queue-style shadow rows** (`source` discriminator + boot-time reconcile). Ship in 4 independently deployable stages, each with a one-revert rollback.

---

## 0. Ground truth constraints (from audit + code read)

- All ~50 platform tools are `execution_mode: :app` with a 1:1 `InternalTools::*` handler class coupled to the DB row only by the `name.camelize` convention (`InternalToolExecutor#resolve_handler`). Schemas live in `db/seeds/platform_tools.rb`; behavior lives in the handler. This is the drift to kill.
- FKs that must survive: `tool_results.tool_id → tools.id` (no `on_delete`, i.e. RESTRICT), `session_tools.tool_id → tools.id` (CASCADE on session delete). Workflow `steps.tool_ids` (jsonb) and `workflows.config["base_tool_ids"]` reference tools **by integer id**.
- The `tools` unique index is `(scope_type, scope_id, name) WHERE deleted_at IS NULL` — platform rows have NULL scope, and Postgres treats NULLs as distinct, so **platform-tool name uniqueness is app-level only today**. The reconciler cannot `ON CONFLICT` against this index; a new partial index is required.
- Three gating mechanisms exist for one idea: `tools.requires_integration` column (pickers only), `Integrations::ManagedMCPToolRegistry` (Coder), in-handler checks (`SlackPostMessage`).
- **Latent bug found during the read (motivating evidence):** `aixle_builder_controller.rb:24` queries `Tool.where(kind: :workflow, name: meta_names)` but migration `20260627000002` moved those rows to `kind: :meta`; additionally `SessionService#scoped_resources` runs attachments through `visible_for_project`, which excludes `:meta`. The Builder apparently attaches **zero** meta tools today. The kind enum is so muddled that a data migration silently broke an attachment path. Verify in staging; hotfix in Stage 0.
- actionmcp facts (research, treated as ground truth): no resolver extension point through 0.111.1, so the monkey-patch stays regardless; upgrading to 0.111.x requires rewriting the overrides (5-arg `send_tools_call`, cursor pagination, dropped 2025-03-26 protocol). The gem's own `ToolsRegistry` is process-global and reset on every dev reload — we deliberately do **not** register anything into it.

---

## 1. Registry design

### 1.1 Where tool definitions live

**On the handler classes themselves.** The 52 `InternalTools::*` classes already exist, one per tool, under a single Zeitwerk-managed namespace. The seed hashes move verbatim into a class-level `tool do ... end` block on each handler. No parallel definitions tree (that would recreate two-place drift one layer over — the exact failure mode the research flags for FrozenRecord/YAML manifests).

```ruby
# app/services/internal_tools/slack_post_message.rb
module InternalTools
  class SlackPostMessage < Base
    tool do
      display_name "Slack Post Message"
      description  "Send a Slack message from this workflow. `text` and `files` are both optional " \
                   "but at least one is required..."
      tags         :messaging, :slack
      inject_when  :workflow_step_session          # replaces kind: :workflow auto-injection
      requires_integration :slack                  # replaces column + in-handler check + registry
      input_schema(                                # raw JSON-Schema hash, moved verbatim from seeds
        type: "object",
        properties: {
          text:  { type: "string", description: "Message text. Optional when files are provided." },
          files: { type: "array", description: "...", items: { "..." => "..." } },
          channel:   { type: "string", description: "..." },
          thread_ts: { type: "string", description: "..." }
        },
        required: []
      )
    end

    def execute
      # unchanged handler body; the in-handler Slack check stays as call-time defense in depth
    end
  end
end
```

More examples covering every current kind:

```ruby
# kind :internal, injected when the session has container tools
class ReadToolResult < Base
  tool do
    display_name "Read Tool Result"
    description  "Retrieve status and download URLs for an async tool execution..."
    tags         :async_results
    inject_when  :container_tools_present
    input_schema(type: "object",
                 properties: { tool_result_id: { type: "string", description: "Execution ID (e.g. tr-abc123...)" } },
                 required: %w[tool_result_id])
  end
end

# kind :internal session-lifecycle, injected for non-interactive sessions
class FinishSession < Base
  tool do
    display_name "Finish Session"
    tags         :session_lifecycle
    inject_when  :non_interactive_session
    input_schema(...)
  end
end

# kind :system Coder tool, surfaced via the managed MCP server
class CoderSshExec < Base
  tool do
    display_name "Coder SSH Exec"
    tags         :coder
    managed_mcp_provider :coder                  # replaces Integrations::ManagedMCPToolRegistry
    requires_integration :coder
    input_schema(...)
  end
end

# kind :meta Aixle Builder tool: not injected, not user-pickable, attached by tag
class MetaCreateTool < Base
  tool do
    display_name "Meta Create Tool"
    tags         :builder
    user_attachable false                        # replaces the :meta picker exclusion
    input_schema(...)
  end
end
```

### 1.2 DSL + Definition PORO

```ruby
# app/services/tools/definition.rb
module Tools
  class Definition
    ATTRS = %i[name display_name description input_schema tags inject_rules
               requires_integration availability unavailable_message
               user_attachable managed_mcp_provider handler_class_name legacy_kind].freeze
    attr_reader(*ATTRS)

    def initialize(**attrs) = ATTRS.each { |a| instance_variable_set(:"@#{a}", attrs[a]) }

    # Reload-safe: store the class NAME, constantize at call time
    # (maintenance_tasks safe_constantize pattern).
    def handler_class = handler_class_name.constantize

    def available?(ctx)
      return false if requires_integration && !ctx.connected?(requires_integration)
      availability.nil? || availability.call(ctx)
    end

    def inject?(ctx) = inject_rules.any? { |r| Tools::INJECTION_RULES.fetch(r).call(ctx) }

    def unavailable_message
      @unavailable_message ||
        "The #{requires_integration} integration is not connected for this project. " \
        "Connect it in Project Settings → Integrations."
    end

    # Projection into the shadow row. legacy `kind` is written through Stage 3
    # so a rollback to old code keeps working bit-for-bit.
    def to_row_attributes(now: Time.current)
      { name: name, display_name: display_name, description: description,
        input_schema: input_schema, tags: tags.map(&:to_s),
        requires_integration: requires_integration&.to_s,
        user_attachable: user_attachable, execution_mode: "app",
        source: "code", kind: legacy_kind.to_s, enabled: true, deleted_at: nil,
        scope_type: nil, scope_id: nil, created_at: now, updated_at: now }
    end
  end
end

# app/services/tools/definition_dsl.rb — extended into InternalTools::Base
module Tools
  module DefinitionDSL
    def tool(&block)
      b = Builder.new(default_tool_name)
      b.instance_eval(&block)
      @tool_config = b.to_h.merge(handler_class_name: name)
    end

    def tool_defined? = instance_variable_defined?(:@tool_config)
    def tool_definition = Definition.new(**@tool_config)
    def default_tool_name = name.demodulize.underscore # existing camelize convention, inverted

    class Builder
      def initialize(name)
        @h = { name: name, tags: [], inject_rules: [], user_attachable: true,
               input_schema: { type: "object", properties: {}, required: [] } }
      end
      def display_name(v)          = @h[:display_name] = v
      def description(v)           = @h[:description] = v
      def input_schema(v)          = @h[:input_schema] = v.deep_stringify_keys
      def tags(*v)                 = @h[:tags] = v
      def inject_when(*rules)      = @h[:inject_rules] = rules   # validated against INJECTION_RULES keys
      def requires_integration(v)  = @h[:requires_integration] = v
      def availability(l = nil, &b)= @h[:availability] = l || b  # escape hatch for non-integration predicates
      def unavailable_message(v)   = @h[:unavailable_message] = v
      def user_attachable(v)       = @h[:user_attachable] = v
      def managed_mcp_provider(v)  = @h[:managed_mcp_provider] = v
      def legacy_kind(v)           = @h[:legacy_kind] = v        # transition-only; see Stage 1
      def to_h = @h
    end
  end
end
```

`legacy_kind` is derived automatically when not set: `inject_when :workflow_step_session` → `workflow`; `:container_tools_present`/`:non_interactive_session` → `internal`; `tags :builder` → `meta`; else `system`. It exists purely so shadow rows stay byte-compatible with old code until Stage 4.

### 1.3 Discovery — Zeitwerk-safe registry

**Chosen pattern: `eager_load_namespace` + `descendants` computed lazily, memo invalidated in `to_prepare`** — pattern (a) from the research (Shopify maintenance_tasks / Avo / ViewComponent), combined with the "store class-name strings, constantize at call time" rule. Chosen over pattern (b) (explicit initializer registry à la Flipper/GoodJob) because the classes already live under one namespace and no per-tool registration call should exist to forget — the whole point is that *writing the class is the registration*. The memo caches only frozen `Definition` POROs (data + name strings), never class objects, so nothing stale survives a dev reload; `to_prepare` (which Zeitwerk guarantees runs on every reload, possibly twice — reset is idempotent) drops the memo.

```ruby
# app/services/tools/registry.rb
module Tools
  module Registry
    class << self
      def definitions
        @definitions || build # benign race under Puma threads: both writers produce identical frozen values
      end

      def fetch(name)        = definitions[name.to_s]
      def names              = definitions.keys
      def tagged(tag)        = definitions.values.select { |d| d.tags.include?(tag) }
      def injectable         = definitions.values.reject { |d| d.inject_rules.empty? }
      def managed_tool_names(provider)
        return [] if provider.blank?
        definitions.values.select { |d| d.managed_mcp_provider.to_s == provider.to_s }.map(&:name)
      end
      def digest
        Digest::SHA256.hexdigest(definitions.values.map { |d| d.to_row_attributes(now: nil).except(:created_at, :updated_at) }
                                            .sort_by { |h| h[:name] }.to_json)
      end
      def reset! = @definitions = nil

      private

      def build
        Rails.autoloaders.main.eager_load_namespace(InternalTools) unless Rails.application.config.eager_load
        defs = InternalTools::Base.descendants.select(&:tool_defined?).map(&:tool_definition)
        dup = defs.group_by(&:name).select { |_, v| v.size > 1 }.keys
        raise "Duplicate tool definitions: #{dup.join(', ')}" if dup.any?
        @definitions = defs.index_by(&:name).freeze
      end
    end
  end
end

# config/initializers/tools_registry.rb
Rails.application.config.to_prepare { Tools::Registry.reset! }
```

### 1.4 Shadow rows + reconciler (Solid Queue pattern)

Rows stay; humans stop writing them. `tools.source` discriminates: `"code"` rows are a **projection owned by the reconciler**; `"db"` rows (user custom tools) are authored data. All FKs keep working unchanged.

```ruby
# app/services/tools/reconciler.rb
module Tools
  class Reconciler
    LOCK_KEY = "aixle_tools_reconcile"

    def self.run!
      return unless Tool.table_exists? && Tool.column_names.include?("source") # pre-migration boot safety

      Tool.transaction do
        Tool.connection.execute("SELECT pg_advisory_xact_lock(hashtext('#{LOCK_KEY}'))")
        rows = Registry.definitions.values.map(&:to_row_attributes)
        Tool.upsert_all(rows, unique_by: :index_tools_on_name_where_source_code) if rows.any?
        # Removed-from-code platform tools: SOFT delete only (tool_results FK is RESTRICT;
        # history must survive). Never destroy, unlike Solid Queue's delete_all.
        Tool.where(source: "code", deleted_at: nil)
            .where.not(name: Registry.names)
            .update_all(deleted_at: Time.current, enabled: false, updated_at: Time.current)
      end
    end
  end
end
```

**When it runs:**
1. **Deploy:** the existing `platform_tools:seed` rake task is repointed at `Tools::Reconciler.run!` — deploy pipelines don't change at all.
2. **Boot (self-heal):** `config.after_initialize { Tools::Reconciler.run! }` guarded by the advisory xact lock, the column-existence check, `ENV["AIXLE_TOOLS_RECONCILE_ON_BOOT"] != "0"`, and skipped in `test`. A forgotten rake step can no longer strand a new tool: ~50-row `upsert_all` is one statement, herd-safe under the lock.
3. **Lazy fallback:** `Tool.shadow_for(defn)` (`find_by(name:, source: "code") || (Reconciler.run!; find_by!(...))`) is called anywhere a row is needed for an FK before reconcile happened (e.g. `ToolResult.create!` in the MCP patch). Covers the race window completely — this is what makes "platform tools available without pre-created DB rows" literally true: the class alone suffices; rows materialize on demand.

**Drift guard:** `rake tools:check` (run in CI and callable in prod, report-only): every definition name matches the MCP `[A-Za-z0-9_.-]` guidance and the app's `/\A[a-z][a-z0-9_]*\z/`; every handler instantiates; every schema is `type: "object"` with no root `$ref`; DB `source="code"` rows diff cleanly against the registry; **no `source="db"` row collides with a registry name** (platform-namespace protection — also enforced going forward by a `Tool` validation on create for db-source rows).

### 1.5 Unification with DB custom tools at tools/list time

Both sides remain `Tool` AR rows at the serving layer (duck-typing is unnecessary because shadow rows exist) — the smallest possible change to `available_tools`, `session_tools` attachment, `ToolResult` creation, and the Temporal path. The definition is still authoritative for *metadata*: `Tool#definition` resolves the registry entry for `source: "code"` rows, and MCP serialization prefers it (a stale row between deploy and reconcile can never serve a stale schema):

```ruby
# app/models/tool.rb
def definition = code_source? ? Tools::Registry.fetch(name) : nil

def available?(ctx)
  return false unless enabled? && !deleted?
  if (d = definition) then d.available?(ctx)
  elsif requires_integration.present? then ctx.connected?(requires_integration) # db-source rows keep column semantics
  else true
  end
end
```

---

## 2. Tagging taxonomy

Three orthogonal axes replace the single muddled `kind` enum (per the research consensus: domain tags / namespacing / behavior flags are distinct axes, and tags must *do* something or they rot):

| Axis | Storage | Values | Does what |
|---|---|---|---|
| **`source`** | `tools.source` column (`"code"`/`"db"`) | who owns the definition | replaces custom-vs-platform split; drives reconciler ownership, `platform_tool?`, scope validation |
| **`user_attachable`** | boolean column, projected from definition | `true`/`false` | replaces the `:meta` picker exclusion; drives `visible_for_project/company` |
| **`tags`** | `tools.tags` jsonb + `Definition#tags`, closed vocabulary | `board`, `workflow_control`, `session_lifecycle`, `async_results`, `messaging`, `slack`, `coder`, `builder` | grouping/lookup (Builder attaches `tagged(:builder)`), UI facets, optional `_meta["ai.aixle/tags"]` on the wire |
| **injection** (behavior, not a tag) | `Definition#inject_rules` — code only, never a column | named rules below | replaces kind-driven auto-injection in `available_tools` |
| **managed serving** (behavior) | `Definition#managed_mcp_provider` — code only | `:coder` | replaces `Integrations::ManagedMCPToolRegistry` |

**Kind → new model mapping (mechanical, verified against every current use):**

| Current kind | source | user_attachable | tags | inject_when | notes |
|---|---|---|---|---|---|
| `custom` | `db` | true | — | — | unchanged UX; scope + docker_image validations key off `source == "db"` now |
| `system` (coder_*) | `code` | true | `coder` | — | + `managed_mcp_provider :coder`, `requires_integration :coder` |
| `internal` (read_tool_result) | `code` | true* | `async_results` | `container_tools_present` | *today `internal` appears in `visible_for_project` despite the "invisible" comment — behavior preserved exactly |
| `internal` (finish/fail_session) | `code` | true* | `session_lifecycle` | `non_interactive_session` | `session_lifecycle_tools` scope is already name-based; becomes tag-based |
| `workflow` (board_*, list_sub_steps, mark_sub_step, slack_post_message) | `code` | true | `board`/`workflow_control`/`slack` | `workflow_step_session` | slack_post_message also `requires_integration :slack` |
| `meta` (meta_*) | `code` | **false** | `builder` | — | attached explicitly by Builder via `Registry.tagged(:builder)` — fixes the latent bug |

**Injection rules** — the current `available_tools` logic expressed as named predicates:

```ruby
# app/services/tools/injection_rules.rb
module Tools
  INJECTION_RULES = {
    workflow_step_session:   ->(ctx) { ctx.session_type == "workflow_step" },
    container_tools_present: ->(ctx) { ctx.candidate_tools.any? { |t| t.execution_mode.container? } },
    non_interactive_session: ->(ctx) { ctx.mode == "non_interactive" }
  }.freeze
end
```

`TerminalSession#available_tools` after cutover (Stage 3) — same shape, two phases because `container_tools_present` depends on the base set, exactly as today:

```ruby
def available_tools(ctx: Tools::Context.for_session(self))
  base = tools.enabled.not_deleted.to_a                                   # explicitly attached
  if base.none? { |t| t.source == "db" } && project.present?
    base += Tool.for_project(project).enabled.to_a                        # custom-tools fallback, unchanged
  end
  ctx.candidate_tools = base
  injected = Tools::Registry.injectable.select { |d| d.inject?(ctx) }
  base += Tool.where(source: "code", name: injected.map(&:name)).enabled.not_deleted.to_a
  base.uniq.select { |t| t.available?(ctx) }                              # NEW: availability filter, one choke point
end
```

The Aixle Builder attach path (Stage 3, also the Stage 0 hotfix in kind terms):

```ruby
# aixle_builder_controller.rb
meta_tool_ids = Tool.where(source: "code", name: Tools::Registry.tagged(:builder).map(&:name)).pluck(:id)
# SessionService gains an explicit bypass for these: attach via
# Tool.where(source: "code", id: ids) when session.metadata["aixle_builder"],
# instead of routing hidden tools through visible_for_project (which correctly excludes them).
```

---

## 3. Availability predicate

**Signature:** `available?(ctx) -> bool` on both `Tools::Definition` and `Tool` (row), where `ctx` is:

```ruby
# app/services/tools/context.rb
module Tools
  class Context
    attr_reader :project, :company, :session, :mode, :session_type
    attr_accessor :candidate_tools   # set during available_tools phase 1

    def self.for_session(session)
      new(project: session.project, company: session.project&.company || session.user&.company,
          session: session, mode: session.mode, session_type: session.session_type)
    end

    def self.for_project(project)   # pickers / SessionConfigResolver: no session
      new(project: project, company: project.company)
    end

    def initialize(project:, company:, session: nil, mode: nil, session_type: nil)
      @project, @company, @session, @mode, @session_type = project, company, session, mode, session_type
      @candidate_tools = []
    end

    # ONE batched query per request, memoized on the ctx object itself —
    # deliberately NOT CurrentAttributes (per the thoughtbot leak incident and the
    # research warning about SSE streams / Temporal threads escaping Rack reset).
    def connected?(provider) = connected_providers.include?(provider.to_s)

    def connected_providers
      @connected_providers ||= begin
        return Set.new if company.nil?
        scope = Integration.active.where(company_id: company.id)
        scope = scope.where("project_id IS NULL OR project_id = ?", project.id) if project
        scope = scope.where(project_id: nil) unless project
        Set.new(scope.distinct.pluck(:provider).map(&:to_s))
      end
    end
  end
end
```

**Declaration:** `requires_integration :slack` covers ~all cases; `availability ->(ctx) { ... }` is the escape hatch (AND-ed after the integration check). A future Flipper policy layer AND-s in here too, never conflated with the capability check.

**Where it is evaluated (one declaration, two evaluation strategies):**

1. **`tools/list` (hide):** the `available_tools` choke point above — ctx built once per request, one integration query total.
2. **`tools/call` (enforce + actionable error):** resolution happens against the *unfiltered* entitled set, then the predicate splits outcomes per the research's entitlement-boundary rule:
   - entitled but unavailable → normal result whose content is the actionable error (`exit_code: 1`, `stderr: defn.unavailable_message` through the existing `build_response_content`) so the agent can tell the user to connect Slack;
   - not entitled / unknown → `method_not_found`, leaking nothing.
   In-handler checks (`SlackPostMessage`) **stay** as defense in depth — hiding is not authorization.
3. **UI pickers (`visible_for_project`) and `SessionConfigResolver#project_tool_ids`:** these must remain chainable `Relation`s (`.pluck`, `.where(id:)`, `.count` are used downstream), so the picker path keeps the **existing SQL clause on `requires_integration`** — but the column is now a *projection written by the reconciler from the declaration*, which is what actually unifies the three mechanisms: one place to declare, and the pickers-vs-runtime divergence (today the column exists only if someone remembered it in seeds) is dead. Complex `availability` lambdas are not SQL-expressible; those tools show in pickers and are enforced at list/call time — acceptable, and honest.

```ruby
scope :visible_for_project, ->(project) {
  not_deleted.enabled.where(source: "code", user_attachable: true)
             .or(not_deleted.enabled.where(scope_type: "Company", scope_id: project.company_id))
             .or(not_deleted.enabled.where(scope_type: "Project", scope_id: project.id))
             .where("tools.requires_integration IS NULL OR tools.requires_integration IN (?)",
                    active_integration_providers(project))   # unchanged SQL, column now reconciler-owned
}
```

**Eventing (best-effort, never load-bearing):** `after_commit` on `Integration` status transitions broadcasts a `list_changed`-style nudge to live sessions; per-request recomputation stays authoritative (client `list_changed` support is unreliable ecosystem-wide). Open item carried from research: consume Slack `tokens_revoked`/`app_uninstalled` events so the Integration row itself stays truthful; poll Coder health.

---

## 4. DB / FK strategy

**What happens to the `tools` table: it stays, gains three columns, loses nothing (until Stage 4).**

```ruby
class AddSourceToTools < ActiveRecord::Migration[8.1]
  def change
    add_column :tools, :source, :string, null: false, default: "db"
    add_column :tools, :user_attachable, :boolean, null: false, default: true
    add_column :tools, :tags, :jsonb, null: false, default: []
    # Reconciler upsert target. NULLs-distinct means the existing (scope_type, scope_id, name)
    # index does NOT enforce platform-name uniqueness — this one does.
    add_index :tools, :name, unique: true,
              where: "source = 'code' AND deleted_at IS NULL",
              name: :index_tools_on_name_where_source_code
  end
end

class BackfillToolSource < ActiveRecord::Migration[8.1]
  class MigrationTool < ActiveRecord::Base; self.table_name = "tools"; end
  def up
    # Pre-check: soft-delete duplicate platform-name rows (keep lowest id) before the unique index bites.
    MigrationTool.where(kind: %w[system internal workflow meta]).update_all(source: "code")
    MigrationTool.where(kind: "meta").update_all(user_attachable: false)
  end
  def down
    MigrationTool.update_all(source: "db", user_attachable: true) # kind untouched; old code never reads source
  end
end
```

(Run the duplicate pre-check inside `up` before adding the index — or split index creation into a follow-up migration after verifying `tools:check` is clean in prod.)

- **`tool_results.tool_id`:** untouched, forever, in this design. Platform executions keep pointing at shadow rows. Removed platform tools are only ever soft-deleted (`deleted_at`), so the RESTRICT FK can never fire and history joins keep working.
- **`session_tools.tool_id`:** untouched. Pickers and `SessionService#attach_resolved_resources` keep attaching by row id; shadow rows are guaranteed present by deploy-time + boot-time reconcile, with `Tool.shadow_for` as the race-window fallback.
- **`steps.tool_ids` / `workflows.config["base_tool_ids"]` (jsonb ids):** untouched. Ids remain per-environment, same as today. Renaming a platform tool follows the existing `MigrationTool` rename pattern (rename the row in a data migration so ids and history survive) — the reconciler alone would soft-delete old + insert new, orphaning step references; `tools:check` flags step references to soft-deleted rows.
- **`kind` column:** kept and *written* by the reconciler (`legacy_kind`) through Stage 3 so any rollback lands on rows old code fully understands. Stage 4: `ignored_columns` for one release, then `remove_column`.
- **Custom-tool trust hardening (creation-time, Stage 1):** `Tool` validation rejects `source: "db"` names colliding with registry names (platform namespace physically protected); `tools:check` reports pre-existing collisions for manual cleanup.

**Rollback story:** every stage before 4 leaves rows that pre-refactor code reads correctly (`kind`, `requires_integration`, schemas all still synced into columns). Rolling back is `git revert` + deploy; no down-migrations needed except to drop the additive columns eventually. Stage 4 is the only door that closes (column drop) and ships last, weeks after cutover.

---

## 5. MCP serving path

**Keep actionmcp 0.104.1 and the monkey-patch shape.** The patch already owns `send_tools_list`/`send_tools_call` wholesale; the diff is contained to that file plus the model methods above.

```ruby
def send_tools_list(request_id, params = {})
  session = current_terminal_session!(request_id) or return
  ctx   = Tools::Context.for_session(session)
  tools = session.available_tools(ctx: ctx)
                 .sort_by(&:name)                                   # deterministic ordering (2026-07-28 RC guidance)
                 .map { |tool| serialize_tool(tool) }
  session.mcp_servers.where(kind: "managed", enabled: true).order(:name).each do |server|
    managed_tools_for(server).each { |t| tools << serialize_tool(t, namespace: server.name) }
  end
  send_jsonrpc_response(request_id, result: { tools: tools })
end

def serialize_tool(tool, namespace: nil)
  defn   = tool.definition                                          # registry-first: stale rows can't serve stale metadata
  schema = (defn&.input_schema || tool.input_schema).presence ||
           { "type" => "object", "properties" => {}, "required" => [] }
  name   = namespace.present? ? "mcp__#{namespace}__#{tool.name}" : tool.name
  h = { "name" => name,
        "description" => defn&.description || tool.description || tool.display_name,
        "inputSchema" => schema.deep_stringify_keys }
  h["_meta"] = { "ai.aixle/tags" => defn.tags.map(&:to_s) } if defn&.tags&.any?  # reverse-DNS per spec
  h
end

def send_tools_call(request_id, tool_name, arguments, _meta = {})
  session = current_terminal_session!(request_id) or return
  ctx = Tools::Context.for_session(session)
  # managed-namespace parsing unchanged
  tool = resolve_tool_for_call(session, resolved_name, mcp_server, ctx: ctx)  # resolves in UNFILTERED entitled set
  return send_jsonrpc_error(request_id, :method_not_found, "Tool '#{tool_name}' not available") unless tool

  unless tool.available?(ctx)   # entitled but disconnected → actionable, model-visible error
    result = { exit_code: 1, stdout: "", stderr: tool.definition&.unavailable_message || "Tool unavailable" }
    return send_jsonrpc_response(request_id, result: { content: build_response_content(result) })
  end
  # execute_tool unchanged, except ToolResult.create! uses Tool.shadow_for when needed
end

def managed_tools_for(server)
  names = Tools::Registry.managed_tool_names(server.integration&.provider)   # was ManagedMCPToolRegistry
  return [] if names.empty?
  Tool.where(source: "code", name: names).enabled.not_deleted.to_a
end
```

- **Managed servers / Coder namespacing: unchanged on the wire.** `mcp__<server>__<tool>` parsing, per-integration `MCPServer` rows, in-process dispatch with `mcp_server` context all stay. `Integrations::ManagedMCPToolRegistry` becomes a one-line shim delegating to `Tools::Registry.managed_tool_names` for one release, then is deleted.
- **`InternalToolExecutor`:** `resolve_handler` prefers `tool.definition&.handler_class`, falling back to the camelize convention (db-source app-mode tools, if any ever exist); `validate_params!` validates against `definition.input_schema` when present.
- **Gem upgrade is deliberately deferred to Stage 4** as an independent project: rewriting the overrides against 0.111.x (5-arg `send_tools_call` with `task_params`, cursor pagination in `send_tools_list`, documented conscious bypass of consent/tasks/strict-params) buys protocol currency but touches nothing in this design's data model — clean separation is the point of Design A. Until then, pin `~> 0.104.0` **exactly** so a bundle update can't silently break the 4-arg override.

---

## 6. Migration outline (ordered, independently shippable)

**Stage 0 — hotfix (independent, ships this week).** Fix the latent Builder bug in kind terms (`kind: :meta` in the controller + an explicit attach path for meta tools in `SessionService`) with regression tests. De-risks Stage 3, which touches exactly this area. Rollback: revert.

**Stage 1 — registry + shadow rows (no serving behavior change).**
1. Migrations: `AddSourceToTools` (+ duplicate pre-check), `BackfillToolSource`.
2. Ship DSL, `Registry`, `Reconciler`, `Tool#definition`, `shadow_for`, custom-name collision validation, `tools:check`.
3. Port all ~50 seed entries into `tool do ... end` blocks (mechanical; schemas copied verbatim).
4. **Parity gate:** a test fixture generated from the current `Seeds::PlatformTools` output; assert `Reconciler` produces identical `(name, kind, display_name, description, input_schema, execution_mode, requires_integration)` rows. Delete seeds file + rake internals in the same PR once green; `platform_tools:seed` now calls the reconciler (deploy pipeline unchanged). Boot reconcile enabled behind `AIXLE_TOOLS_RECONCILE_ON_BOOT` (default on).
- *Rollback:* revert code; restore seeds file from git. New columns are inert to old code.

**Stage 2 — availability unification.**
1. Ship `Tools::Context`, `Definition#available?`, `Tool#available?`.
2. Patch `send_tools_list` (filter + deterministic sort + registry-first serialization) and `send_tools_call` (enforce + actionable error).
3. `requires_integration` column becomes reconciler-owned (declarations added to `SlackPostMessage`, `Coder*`); picker SQL untouched. Add `requires_integration :coder` to coder tools — this newly hides them in pickers/lists without a Coder integration, the desired behavior change; everything else is behavior-neutral.
- *Rollback:* revert; column data still valid for the old SQL path.

**Stage 3 — taxonomy cutover.**
1. Rewrite `available_tools` on injection rules (old kind-based body kept behind `ENV["AIXLE_LEGACY_AVAILABLE_TOOLS"]` for one release as an instant kill switch).
2. Builder attaches via `Registry.tagged(:builder)`; `session_lifecycle_tools`/`workflow_tools`/`internal_tools`/`system_tools` scopes rewritten to tag/source equivalents; `ManagedMCPToolRegistry` shim deleted; `visible_for_project` moves to `source`/`user_attachable`.
- *Rollback:* flip the env flag, or revert — `kind` is still being written by the reconciler.

**Stage 4 — cleanup + gem upgrade (each independent).**
1. Stop writing `kind` → `ignored_columns` → drop column (two releases).
2. actionmcp `~> 0.111` upgrade with rewritten overrides; protocol note: 2025-03-26 clients break — audit connected agent runtimes first.
3. Optional: `container do ... end` block in the DSL folding `InternalToolStrategy.define` for future container-mode platform tools; Flipper policy layer AND-ed into `available?`.

---

## 7. Trade-offs (named honestly)

- **Residual duplication accepted:** shadow rows duplicate definition metadata. It is *synced* duplication (reconciler-owned, drift window = deploy-to-boot, closed by boot reconcile + lazy `shadow_for`), not *authored* duplication — the human failure mode is gone, the mechanical one is monitored by `tools:check`.
- **Rows are still required for attach-by-id UX** (`session_tools`, `steps.tool_ids`). True row-less serving (string-key references everywhere, Solid-Queue-executions-style) is a Design B/C; retrofitting it would touch every workflow/step/picker path for no user-visible gain.
- **The monkey-patch lives on** and the actionmcp upgrade debt is scheduled, not paid. Mitigated by exact-pinning the gem and isolating all new logic in `Tools::*` so a future patch rewrite (or a move to the official `mcp` gem) reuses `Registry`/`Context`/`Definition` unchanged — those are gem-agnostic by construction.
- **Picker gating stays SQL-only for the simple case;** complex availability lambdas are enforced only at list/call. Accepted: pickers are advisory UI, runtime is the boundary.
- **Renames still need data migrations** (id continuity), same as today — the registry does not remove that class of migration, only the create/update class.
