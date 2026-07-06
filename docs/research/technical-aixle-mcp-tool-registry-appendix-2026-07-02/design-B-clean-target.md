KEY DECISIONS:
- One Ruby class per platform tool in app/tools/platform_tools/ co-locating name, schema (param DSL), tags, availability, annotations, and handler/container definition — adding a tool is one file, zero registration, zero seed
- Discovery via eager_load_namespace(PlatformTools) + PlatformTool.descendants, memoized and reset in to_prepare (maintenance_tasks + Flipper hybrid) — no boot-time class caching, no manual register calls
- Replace the kind enum with orthogonal axes: structural source (platform-class vs custom-row), closed domain tags, surface (:picker/:builder), and an inject-trigger enum (:workflow_step_session, :container_tools_present, :non_interactive_session) that reproduces available_tools' four injection branches as tag queries in Toolset.for_session
- Single availability predicate available?(Tools::Context) unifying requires_integration column, ManagedMCPToolRegistry, and in-handler checks; evaluated at tools/list (hide), tools/call (enforce: isError+remedy for entitled-but-disconnected, method_not_found otherwise), UI pickers, and auto-injection; fed by one batched IntegrationSet query memoized in a declared CurrentAttributes attribute
- Canonical string ToolKey ('platform:<name>' / 'custom:<id>') replaces integer references: terminal_sessions.tool_keys jsonb replaces the session_tools join table, steps/workflows get tool_keys/base_tool_keys jsonb, tool_results gets authoritative tool_key plus a nullable custom_tool_id FK kept only for custom rows
- Swap actionmcp (0.104.1 + wholesale monkey-patch) for the official mcp gem's stateless server-per-request controller — the patch, gateway, and engine mount are deleted; custom DB tools enter via MCP::Tool.define; Coder's mcp__<server>__<tool> namespacing survives as a ManagedAlias decorator
- Keep the execution_id + read_tool_result polling contract for async container tools (only interop-safe mechanism in mid-2026; MCP Tasks are a moving target per SEP-2663), hardened with echoed id + poll-interval hint
- Migration is 6 independently deployable stages; Stage 1 (registry-driven row reconciler replacing Seeds::PlatformTools, Solid Queue pattern) kills class/seed drift on day one before any FK or serving change; destructive drops (platform rows, session_tools, kind column, tools→custom_tools rename) come last after bake + verification queries
- tools table ends as custom_tools holding only user-created docker tools; meta_create_tool and Aixle Builder flows unchanged except the Builder attaches by surface: :builder tag query (also fixing the live kind: :workflow vs :meta mismatch in aixle_builder_controller.rb:24)

RISKS:
- Big-bang port of ~52 handler classes + seed schemas into PlatformTool classes has a wide regression surface — the golden parity spec mitigates metadata drift but not behavioral edge cases in moved handler bodies
- Stage 5 is irreversible for platform-row ids: after rows are deleted and tool_results.tool_id nulled, rollback to the id scheme cannot restore original ids — requires strict bake time and zero-orphan verification queries before shipping
- Official mcp gem API churn (0.22.x): handle_request return shape, Tool::Response error kwarg, and annotations class must be verified at implementation time; the design sketches them from research, not from pinned source
- Hiding integration-gated tools at list time changes agent behavior versus today's visible-tool-with-runtime-error — workflow prompts that reference slack_post_message/coder_* by name will see no such tool when the integration is absent
- CurrentAttributes-memoized IntegrationSet leaks across requests if any non-Rack path (Temporal activity threads, SSE streams) touches Toolset without Executor.wrap/reset — needs an explicit wrapper and a test
- Stale/duplicate legacy data complicates backfill: jsonb tool_ids arrays already contain dangling ids, and the NULLs-distinct unique index allowed duplicate platform rows (e.g. meta_* names under both workflow and meta kinds) — the backfill must dedupe and log-drop unknowns
- In-flight agent containers during the Stage 3 endpoint swap hold /action_mcp configs and possibly older protocol versions — the alias route covers the path, but protocol-version negotiation differences between actionmcp and the mcp gem need a session-drain or compatibility window
- Losing list_changed push entirely (stateless transport) means availability flips mid-session are only visible on the next client tools/list — acceptable per research, but a UX regression if a client caches aggressively (Cursor freezes lists until restart)
- String-key referential integrity moves to the app: a hard-deleted custom tool leaves orphaned custom:<id> keys in workflow/step configs that now fail at resolution instead of being FK-prevented

# Aixle Code-First MCP Tool Registry — Target-State Architecture (Design B)

**Lens:** clean destination, migration cost secondary but staged and survivable. One class per platform tool; string keys replace FKs; actionmcp replaced by the official `mcp` gem's server-per-request idiom.

Existing files referenced throughout: `/Users/artem_petrov/projects/personal/app/app/models/tool.rb`, `/Users/artem_petrov/projects/personal/app/app/models/terminal_session.rb`, `/Users/artem_petrov/projects/personal/app/config/initializers/action_mcp_dynamic_tools.rb`, `/Users/artem_petrov/projects/personal/app/db/seeds/platform_tools.rb`, `/Users/artem_petrov/projects/personal/app/app/services/integrations/managed_mcp_tool_registry.rb`.

---

## 0. Target state in one paragraph

Every platform tool is **one Ruby class** under `app/tools/platform_tools/` co-locating wire name, description, input schema, tags, availability predicate, annotations, and the handler (or container definition). Discovery is Zeitwerk-safe class enumeration — no registration call, no seed, no DB row. The `tools` table is renamed `custom_tools` and holds **only user-created docker tools** (docker_image + command + input_schema + tool_files, Company/Project scoped). All references to tools (session attachments, workflow/step configs, execution results) use a canonical **string ToolKey** (`platform:slack_post_message` / `custom:123`). A single `Toolset` assembles code entries + DB entries behind one duck type for `tools/list`, `tools/call`, UI pickers, and auto-injection. MCP is served by the official `mcp` gem, building a stateless server per request from the authenticated `TerminalSession` — the actionmcp monkey-patch, gateway, engine mount, `Seeds::PlatformTools`, `InternalToolExecutor`, and `ManagedMCPToolRegistry` are all deleted.

```
                    ┌────────────────────────────────────────────┐
                    │                 Toolset                    │
                    │  (assembly + injection rules + availability)│
                    └──────────┬─────────────────┬───────────────┘
   code, zero ceremony         │                 │        DB, user-authored
┌──────────────────────────────▼──┐   ┌──────────▼──────────────────────┐
│ PlatformToolRegistry            │   │ CustomTool (AR, custom_tools)   │
│ PlatformTool.descendants        │   │ docker_image/command/schema/    │
│ app/tools/platform_tools/**     │   │ tool_files, scope, soft delete  │
└─────────────────────────────────┘   └─────────────────────────────────┘
        consumers: Mcp::ServerController (official mcp gem, stateless per request),
        UI pickers, SessionConfigResolver, Aixle Builder, Temporal execution path
```

---

## 1. Registry design

### 1.1 Where tool classes live

```
app/tools/
  platform_tool.rb                    # PlatformTool (abstract base + DSL)
  platform_tool_registry.rb           # discovery + lookup
  tool_key.rb                         # canonical string-key value object
  tools/context.rb                    # availability context (see §3)
  toolset.rb                          # unification layer (see §1.5)
  custom_tool_entry.rb                # duck-typed wrapper over CustomTool rows
  platform_tools/
    board/
      add_comment.rb                  # PlatformTools::Board::AddComment  → "board_add_comment"
      list_tasks.rb                   # …all 12 board tools
    coder/
      allocate_machine.rb             # → "coder_allocate_machine"
      ssh_exec.rb
      release_machine.rb
    meta/
      create_tool.rb                  # → "meta_create_tool" …all 28 meta tools
    workflow/
      list_sub_steps.rb
      mark_sub_step.rb
    session/
      finish_session.rb
      fail_session.rb
      read_tool_result.rb
    slack_post_message.rb             # PlatformTools::SlackPostMessage
```

`app/tools` is an autoload root automatically (Rails app/* convention). Wire names are derived from the class path minus the `PlatformTools::` root (`Board::AddComment` → `board_add_comment`), overridable with `tool_name`. Namespacing-by-directory doubles as the provider/service grouping axis the research found the ecosystem uses instead of tags (`coder_*`, `board_*`, `meta_*` prefixes).

The current `InternalTools::*` handler bodies move into these classes verbatim (mechanical port); `InternalTools::Base` helpers (`success`/`error`/`require_workflow_context!`/`project`/`step_run`/`workflow_run`) move onto `PlatformTool`. `InternalToolExecutor` and its `name.camelize` convention die — the class *is* the handler.

### 1.2 Base class + DSL (concrete)

```ruby
# app/tools/platform_tool.rb
class PlatformTool
  Result = Struct.new(:exit_code, :stdout, :stderr, keyword_init: true)

  class_attribute :abstract_tool, default: false
  def self.abstract! = (self.abstract_tool = true)

  class << self
    # ---- identity ----
    def tool_name(value = nil)
      @tool_name = value.to_s if value
      @tool_name ||= name.delete_prefix("PlatformTools::").gsub("::", "_").underscore
    end

    def key = "platform:#{tool_name}"
    def wire_name = tool_name

    def display_name(value = nil)
      @display_name = value if value
      @display_name ||= tool_name.titleize
    end

    def description(value = nil)
      @description = value if value
      @description
    end

    # ---- schema: param DSL compiles to JSON Schema; raw override for complex shapes ----
    def param(name, type:, description: nil, required: false, **opts)
      params_spec[name.to_s] = { "type" => type.to_s, "description" => description, **opts.deep_stringify_keys }.compact
      required_params << name.to_s if required
    end

    def input_schema(raw = nil)
      @raw_schema = raw.deep_stringify_keys if raw
      @raw_schema || {
        "type" => "object",
        "properties" => params_spec,
        "required" => required_params
      }
    end

    def params_spec = @params_spec ||= {}
    def required_params = @required_params ||= []

    # ---- taxonomy (see §2) ----
    def tags(domain: nil, surface: nil, inject: nil)
      @tags ||= { domain: [], surface: [], inject: [] }
      @tags[:domain] |= Array(domain).map(&:to_sym) if domain
      @tags[:surface] |= Array(surface).map(&:to_sym) if surface
      @tags[:inject] |= Array(inject).map(&:to_sym) if inject
      @tags
    end

    def tagged?(axis, value) = tags[axis].include?(value)

    # ---- MCP behavior annotations (separate axis, on the wire) ----
    def annotations(read_only: nil, destructive: nil, idempotent: nil, open_world: nil)
      @annotations ||= {}
      { readOnlyHint: read_only, destructiveHint: destructive,
        idempotentHint: idempotent, openWorldHint: open_world }
        .compact.each { |k, v| @annotations[k] = v }
      @annotations
    end

    # ---- availability (see §3) ----
    def requires_integration(*providers)
      integration_requirements.concat(providers.map(&:to_s))
    end
    def integration_requirements = @integration_requirements ||= []

    def available(&block) = (@availability_block = block)
    def availability_block = @availability_block

    def feature_flag(name = nil)
      @feature_flag = name if name
      @feature_flag
    end

    def available?(ctx)
      integration_requirements.all? { |p| ctx.integration?(p) } &&
        (availability_block.nil? || availability_block.call(ctx)) &&
        (feature_flag.nil? || Flipper.enabled?(feature_flag, ctx.company))
    end

    def unavailable_reason(ctx)
      missing = integration_requirements.find { |p| !ctx.integration?(p) }
      return "#{missing.capitalize} is not connected for this project. Connect it in Project Settings → Integrations." if missing
      "This tool is not available in the current context."
    end

    # ---- managed-server exposure (replaces Integrations::ManagedMCPToolRegistry) ----
    def managed_server(provider = nil)
      @managed_server = provider&.to_s if provider
      @managed_server
    end

    # ---- execution ----
    # :app (default) → instance #call in-process. :container → Temporal, via `container do ... end`.
    def execution_mode = @container_definition ? :container : :app

    def container(&block)   # embeds the ContainerStrategies::InternalToolStrategy::Definition
      @container_definition = ContainerStrategies::InternalToolStrategy::Definition.new(tool_name).tap { |d| d.instance_eval(&block) }
    end
    def container_definition = @container_definition
  end

  attr_reader :args, :context
  delegate :session, :project, to: :context

  def initialize(args:, context:)
    @args = (args || {}).with_indifferent_access
    @context = context
  end

  def call
    raise NotImplementedError, "#{self.class}#call must be implemented"
  end

  private

  def success(text) = Result.new(exit_code: 0, stdout: text.to_s, stderr: "")
  def error(text)   = Result.new(exit_code: 1, stdout: "", stderr: text.to_s)

  def step_run = session&.step_run
  def workflow_run = step_run&.workflow_run
  def require_workflow_context!
    raise WorkflowContextError, "This tool requires a workflow context" unless step_run
  end
end
```

A real tool — the whole file, zero ceremony (compare: today this needs a seed entry in `db/seeds/platform_tools.rb` + a handler class + a `requires_integration` column value + an in-handler check):

```ruby
# app/tools/platform_tools/slack_post_message.rb
module PlatformTools
  class SlackPostMessage < PlatformTool
    description "Send a Slack message from this workflow. `text` and `files` are both optional " \
                "but at least one is required. Omit channel/thread to reply where the run was triggered."

    tags domain: :messaging, surface: :picker, inject: :workflow_step_session
    requires_integration :slack
    annotations open_world: true

    param :text,      type: :string, description: "Message text. Optional when files are provided."
    param :channel,   type: :string, description: "Channel ID. Defaults to the triggering channel."
    param :thread_ts, type: :string, description: "Thread timestamp to reply into."
    param :files,     type: :array, description: "Optional file attachments, sent in the SAME message.",
          items: { type: "object",
                   properties: { filename: { type: "string" }, content: { type: "string" }, title: { type: "string" } },
                   required: %w[filename content] }

    def call
      require_workflow_context!
      # …body moved verbatim from InternalTools::SlackPostMessage#execute.
      # The workspace-selection logic (reply through the triggering integration) stays here;
      # the "is Slack connected at all" guard is gone — available?/call-time enforcement owns it.
    end
  end
end
```

A Coder tool declares `managed_server :coder` instead of appearing in `ManagedMCPToolRegistry`:

```ruby
# app/tools/platform_tools/coder/allocate_machine.rb
module PlatformTools
  module Coder
    class AllocateMachine < PlatformTool
      description "Claim a Coder workspace for the current terminal session…"
      tags domain: :coder, surface: :picker
      requires_integration :coder
      managed_server :coder
      param :note, type: :string, description: "Optional allocation note"

      def call = # body from InternalTools::CoderAllocateMachine
    end
  end
end
```

A future container-executed platform tool co-locates its runtime spec (the currently-unused `InternalToolStrategy` DSL finally gets a home):

```ruby
class PlatformTools::RepoScan < PlatformTool
  tags domain: :execution, surface: :picker
  param :repository_id, type: :integer, required: true
  container do
    image "aixle/repo-scan:1.4"
    timeout 900
    memory 2.gigabytes
    cmd { |input| ["/bin/sh", "-c", "scan --repo $REPO"] }
  end
end
```

### 1.3 Discovery — Zeitwerk-safe pattern and why

**Chosen pattern: `eager_load_namespace` + `descendants` computed lazily, memoized, reset in `to_prepare`** — the Shopify `maintenance_tasks` pattern from the research, combined with the Flipper/GoodJob "rebuild on reload" reset. Why this over the alternatives the research surveyed:

- vs. explicit registration calls (current `ManagedMCPToolRegistry` / `InternalToolStrategy.define` style): registration is exactly the ceremony we are eliminating; a forgotten `register` recreates "wrote the class, forgot the seed" one layer over.
- vs. string class names + `safe_constantize` everywhere: we need *enumeration* (pickers, `tools/list`, injection rules), not just point lookup — `descendants` after `eager_load_namespace` is the enumeration-safe idiom.
- vs. a boot-time initializer registry: holds stale classes after the first dev reload (Rails guide: "do not cache reloadable classes"); the `to_prepare` reset removes that hazard, and the reset also covers the actionmcp-style dev-reload `clear!` problem the research flagged.

```ruby
# app/tools/platform_tool_registry.rb
module PlatformToolRegistry
  class UnknownToolError < StandardError; end
  MUTEX = Mutex.new

  module_function

  def all
    MUTEX.synchronize do
      @all ||= begin
        Rails.autoloaders.main.eager_load_namespace(PlatformTools) unless Rails.application.config.eager_load
        PlatformTool.descendants.reject(&:abstract_tool).sort_by(&:tool_name).freeze
      end
    end
  end

  def index    = @index ||= all.index_by(&:tool_name).freeze
  def lookup(name)  = index[name.to_s]
  def fetch(name)   = index.fetch(name.to_s) { raise UnknownToolError, "No platform tool '#{name}'" }
  def where(axis, value) = all.select { |t| t.tagged?(axis, value) }
  def managed_for(provider) = all.select { |t| t.managed_server == provider.to_s }

  def reset!
    MUTEX.synchronize { @all = @index = nil }
  end
end

# config/initializers/platform_tool_registry.rb
Rails.application.config.to_prepare { PlatformToolRegistry.reset! }
```

Deterministic `sort_by(&:tool_name)` satisfies the 2026-07-28 RC's deterministic-ordering ask (client/LLM prompt-cache friendliness).

### 1.4 The canonical ToolKey

```ruby
# app/tools/tool_key.rb
class ToolKey
  FORMAT = /\A(platform|custom):[a-z0-9_]+\z/
  def self.platform(name) = "platform:#{name}"
  def self.custom(id)     = "custom:#{id}"

  # Resolve a key to a Toolset entry within a project scope. Unknown keys resolve
  # to nil (caller decides: skip silently at assembly, error visibly at call).
  def self.resolve(key, project: nil)
    kind, ref = key.to_s.split(":", 2)
    case kind
    when "platform" then PlatformToolRegistry.lookup(ref)
    when "custom"
      row = CustomTool.not_deleted.enabled.find_by(id: ref)
      row && CustomToolEntry.new(row) if row.nil? || row.accessible_from?(project)
    end
  end
end
```

### 1.5 Unification with DB custom tools — the Toolset

Both sides implement one duck type (the GoodJob `CronEntry`-beside-rows pattern the research identified as the ecosystem norm — no FrozenRecord/ActiveHash mirror data):

```
#key #wire_name #display_name #description #input_schema #tags #annotations
#available?(ctx) #unavailable_reason(ctx) #execution_mode #execute(args, ctx) #custom?
```

`CustomToolEntry` wraps a `CustomTool` row: `key = ToolKey.custom(row.id)`, `available?(ctx)` = row enabled + scope matches ctx.project/company (custom tools have no integration gating today; `required_config_items` presence could later join the predicate), `execute` = Temporal via `CustomToolStrategy` (unchanged), `tags` = `{domain: [:custom], surface: [:picker], inject: []}`.

```ruby
# app/tools/toolset.rb
class Toolset
  # Replaces TerminalSession#available_tools. All auto-injection rules from
  # terminal_session.rb:130-153 are expressed as inject-tag queries (§2.3).
  def self.for_session(session, ctx = Tools::Context.for_session(session))
    entries = session.tool_keys.filter_map { |k| ToolKey.resolve(k, project: session.project) }

    entries |= PlatformToolRegistry.where(:inject, :workflow_step_session) if session.session_type == "workflow_step"

    if entries.none?(&:custom?) && session.project
      entries |= CustomTool.for_project(session.project).enabled.map { |r| CustomToolEntry.new(r) }
    end

    entries |= PlatformToolRegistry.where(:inject, :container_tools_present) if entries.any? { |e| e.execution_mode == :container }
    entries |= PlatformToolRegistry.where(:inject, :non_interactive_session) if session.mode == "non_interactive"

    entries.select { |e| e.available?(ctx) }.sort_by(&:wire_name)
  end

  # Replaces Tool.visible_for_project for UI pickers — same predicate, no SQL/Ruby divergence.
  def self.pickable(project)
    ctx = Tools::Context.for_project(project, surface: :picker)
    PlatformToolRegistry.where(:surface, :picker).select { |t| t.available?(ctx) } +
      CustomTool.visible_for_project(project).map { |r| CustomToolEntry.new(r) }
  end

  # Managed-server aliases (Coder namespacing preserved, see §5.3)
  def self.managed_aliases(session)
    session.mcp_servers.managed_servers.enabled.includes(:integration).flat_map do |server|
      PlatformToolRegistry.managed_for(server.integration&.provider).map { |t| ManagedAlias.new(t, server) }
    end
  end
end
```

---

## 2. Tagging taxonomy

Four **orthogonal axes** (matching the three-axis ecosystem consensus from the research, plus Aixle's injection semantics). Small closed vocabularies, enforced by a registry spec — free-form tags are rejected because "tags must do something or they rot."

### 2.1 Axes and values

| Axis | Values (closed) | What it drives |
|---|---|---|
| **source** (structural, not a tag) | `platform` (code class) / `custom` (DB row) | Which side of the registry; key prefix; who may edit |
| **domain** | `board, workflow, messaging, coder, session, meta, execution, custom` | Grouping/search in pickers; `_meta["ai.aixle/tags"]` on the wire; admin UI |
| **surface** | `picker` (user-attachable, UI pickers), `builder` (Aixle Builder only), *(absent = auto-inject only)* | Where a human can attach the tool |
| **inject** | `workflow_step_session`, `container_tools_present`, `non_interactive_session` | Auto-injection triggers evaluated by `Toolset.for_session` — a fixed enum, not arbitrary lambdas, so the rules stay auditable |
| **annotations** | MCP standard `readOnlyHint/destructiveHint/idempotentHint/openWorldHint` | Client confirmation policies; on the wire |

Availability (`requires_integration`, `available` block) is deliberately **not** a tag — it is a predicate (§3). Deferral (`defer_loading`-style) is reserved as a future fifth flag, kept distinct from availability per the research.

### 2.2 How current kinds map

| Today (`kind`) | Tools | Target |
|---|---|---|
| `custom` | user tools | `CustomTool` row — untouched |
| `system` | `coder_*` (3) | platform; `domain: :coder, surface: :picker`; `requires_integration :coder`; `managed_server :coder` |
| `internal` | `read_tool_result` | platform; `domain: :execution`; no surface; `inject: :container_tools_present` |
| `internal` | `finish_session`, `fail_session` | platform; `domain: :session`; no surface; `inject: [:container_tools_present, :non_interactive_session]` (faithful to today: injected by *both* rules via `internal_tools` + `session_lifecycle_tools`) |
| `workflow` | `board_*` (12), `list_sub_steps`, `mark_sub_step` | platform; `domain: :board`/`:workflow`; `surface: :picker`; `inject: :workflow_step_session` |
| `workflow` | `slack_post_message` | platform; `domain: :messaging, surface: :picker, inject: :workflow_step_session`; `requires_integration :slack` |
| `meta` | `meta_*` (28) | platform; `domain: :meta, surface: :builder`; no inject |

One deliberate, small UX change: `read_tool_result`/`finish_session`/`fail_session` no longer appear in `visible_for_project` results (today they do, because that scope includes `kind: internal`); attaching them manually was always meaningless — they arrive via injection.

### 2.3 Auto-injection rules, expressed

The four branches of `TerminalSession#available_tools` (lines 130–153) become the four `Toolset.for_session` steps in §1.5 — `Tool.workflow_tools` → `where(:inject, :workflow_step_session)`; the custom-tools-fallback stays a Toolset rule (it is about *absence of custom entries*, not a property of any tool); `Tool.internal_tools` when container tools present → `where(:inject, :container_tools_present)`; `Tool.session_lifecycle_tools` in non_interactive mode → `where(:inject, :non_interactive_session)`. `TerminalSession#available_tools` remains as a thin delegator to preserve call sites.

The Aixle Builder stops plucking ids by hard-coded name list (and stops querying the wrong kind — `aixle_builder_controller.rb:24` queries `kind: :workflow` for tools seeded as `kind: :meta`, a live drift bug this design retires):

```ruby
tool_keys: PlatformToolRegistry.where(:surface, :builder).map(&:key)
```

`meta_create_tool` keeps creating `CustomTool` rows unchanged, with two added validations from the trust research: reject names colliding with any `PlatformToolRegistry.index` key, and reject the `mcp__` prefix (the current name regex permits it).

---

## 3. Availability predicate

### 3.1 Signature and context

```ruby
tool.available?(ctx) → true/false          # class-level on platform tools, instance on CustomToolEntry
tool.unavailable_reason(ctx) → String      # actionable remedy for call-time errors
```

```ruby
# app/tools/tools/context.rb
module Tools
  class Context
    attr_reader :project, :company, :session, :user, :surface  # :mcp_list | :mcp_call | :picker | :injection

    def self.for_session(session, surface: :mcp_list)
      new(project: session.project, company: session.project&.company || session.user&.company,
          session: session, user: session.user, surface: surface)
    end

    def self.for_project(project, surface: :picker)
      new(project: project, company: project.company, session: nil, user: nil, surface: surface)
    end

    def integration?(provider) = integration_set.include?(provider.to_s)
    def integration_set = @integration_set ||= IntegrationSet.for(project: project, company: company)
  end
end
```

### 3.2 Batched integration loading

One query per request regardless of tool count, memoized in a **declared** `CurrentAttributes` attribute (the thoughtbot undeclared-ivar leak from the research is the explicit anti-pattern here):

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :integration_sets   # Hash{cache_key => IntegrationSet}
end

class IntegrationSet
  def self.for(project:, company:)
    key = [project&.id, company&.id]
    (Current.integration_sets ||= {})[key] ||= begin
      providers =
        if project
          Integration.active
                     .where("(project_id = :pid) OR (project_id IS NULL AND company_id = :cid)",
                            pid: project.id, cid: project.company_id).distinct.pluck(:provider)
        elsif company
          Integration.active.company_wide.where(company_id: company.id).distinct.pluck(:provider)
        else
          []
        end
      new(providers.to_set(&:to_s))
    end
  end

  def initialize(providers) = @providers = providers
  def include?(p) = @providers.include?(p)
end
```

Caveat carried from the research: `CurrentAttributes` reset assumes the Rack executor — the Temporal activity threads that also touch tools must wrap work in `ActiveSupport::Executor.wrap` (or call `Current.reset`) explicitly.

### 3.3 Where it is evaluated — unifying the three mechanisms

| Old mechanism | Replacement |
|---|---|
| `tools.requires_integration` column filtered only in `visible_for_project` (pickers) | `requires_integration :slack` class declaration; evaluated in **all four** places below |
| `Integrations::ManagedMCPToolRegistry` provider→names map | `managed_server :coder` declaration; `PlatformToolRegistry.managed_for(provider)` — file deleted |
| In-handler runtime checks (`SlackPostMessage`, `CoderResolver#require_coder!`) | Call-time enforcement in the serving layer via the same predicate; handlers keep only *selection* logic (which workspace/integration), not *presence* checks |

Evaluation points:

1. **`tools/list`** — `Toolset.for_session` filters with `available?` → unavailable tools are **hidden** (the OpenAI-SDK/LibreChat/Zapier fork of the design choice; smaller lists measurably help agents).
2. **`tools/call`** — enforce, don't trust the list (spec MUST). Two distinct failure shapes per the research's entitlement-leak rule:
   - tool exists in the tenant's entitlement scope but `available?` is false (e.g. Slack disconnected since the list was fetched) → **`isError: true` tool result** with `unavailable_reason(ctx)` — self-describing, lets the agent tell the user to connect Slack;
   - tool unknown / other tenant's custom tool / not in session set → plain protocol **method_not_found** (no remedy text, no capability leak).
3. **UI pickers** — `Toolset.pickable(project)` uses the identical predicate, deleting today's SQL-scope-vs-runtime divergence (currently `requires_integration` gates pickers but *not* `available_tools`).
4. **Auto-injection** — `Toolset.for_session` filters injected entries too, so a workflow session in a project without Slack simply never sees `slack_post_message` (today it sees it and gets a handler error).

**Eventing:** integration connect/disconnect is a local DB write; per-request recomputation is authoritative (the only universally-supported mechanism). With the stateless transport there is no `list_changed` push channel; this is an accepted loss — the research shows push is unreliable across clients anyway, and the actionable call-time error covers stale lists. The Slack `tokens_revoked`/`app_uninstalled` event consumers remain a required companion so the Integration row itself stays truthful (open item, unchanged by this design). Flipper flags are the orthogonal policy layer: `feature_flag "tools.repo_scan"` ANDs into `available?` for rollout/kill-switch, never conflated with capability.

---

## 4. DB / FK strategy

### 4.1 End state

- **`tools` → renamed `custom_tools`**; model `CustomTool` (a `Tool = CustomTool` alias survives one release). Dropped columns: `kind`, `requires_integration` (both now code concerns). Kept: `name, display_name, description, docker_image, command, input_schema, required_config_items, execution_mode, enabled, scope_*, deleted_at`, the partial unique index on `[scope_type, scope_id, name]`. A CHECK/validation `scope_id IS NOT NULL` enforces "every row is user-owned" (today's Postgres NULLs-distinct unique index even allowed duplicate platform rows — e.g. a `meta_*` name under both `workflow` and `meta` kinds).
- **`session_tools` — dropped entirely.** Replaced by `terminal_sessions.tool_keys jsonb NOT NULL DEFAULT '[]'` — consistent with the existing `steps.tool_ids`/`workflows.base_tool_ids` jsonb pattern; sessions are short-lived and never queried by tool relationally.
- **`steps.tool_ids` / `workflows.base_tool_ids` → `tool_keys` / `base_tool_keys`** jsonb string arrays (`["platform:board_add_comment", "custom:42"]`). Bonus: `WorkflowDuplicator#map_tool_ids` only remaps `custom:` keys — platform keys are stable across projects/companies, deleting a whole class of duplication bugs.
- **`tool_results`**: `tool_key varchar NOT NULL` (indexed) is the authoritative reference; `tool_id` → renamed `custom_tool_id`, **nullable**, FK to `custom_tools` `on_delete: :nullify` — kept only for custom executions (cheap joins for "runs of this tool" UI, cascade integrity). Platform executions carry only `tool_key`. This is the research's rank-1 string-key pattern (Solid Queue executions, GoodJob `cron_key`, maintenance_tasks `task_name`), with the FK retained exactly where a real row exists.
- **`tool_files`** — unchanged, FK to `custom_tools` (platform tools never had files).

### 4.2 Migration steps in order (schema only; staging in §6)

1. `add_column :tool_results, :tool_key, :string` + index; `add_column :terminal_sessions, :tool_keys, :jsonb, default: [], null: false`; `add_column :steps, :tool_keys, :jsonb, default: []`; `add_column :workflows, :base_tool_keys, :jsonb, default: []`. Deploy dual-writes (every writer sets both id and key forms).
2. Idempotent backfill data migration (existing `MigrationTool` pattern): `tool_results.tool_key = CASE WHEN t.kind='custom' THEN 'custom:'||t.id ELSE 'platform:'||t.name END` via join; same mapping for the three jsonb arrays and `session_tools` → `terminal_sessions.tool_keys`. Unknown/stale ids in jsonb arrays are dropped with a logged warning (they were already dangling).
3. Flip all readers to keys (`Toolset`, `SessionConfigResolver`, serializers/Typelizer resources, FE pickers send `key` strings).
4. `change_column_null :tool_results, :tool_id, true`; data migration nulls `tool_id` where the referenced row has `kind != 'custom'`.
5. **Destructive stage (last, after bake):** delete platform rows (`Tool.where.not(kind: :custom).delete_all` — safe: no FK references remain); `rename_column :tool_results, :tool_id, :custom_tool_id`; recreate FK `on_delete: :nullify`; drop `session_tools`; drop `steps.tool_ids`, `workflows.base_tool_ids`; drop `tools.kind`, `tools.requires_integration`; `rename_table :tools, :custom_tools`.

### 4.3 Rollback story

- Stages 1–4 are additive/dual-write: rollback = flip readers back to id columns (still populated).
- Stage 5 is the point of no return for *platform rows and their old ids*. Mitigations: a `tools:materialize_platform_rows` rake task can regenerate rows from the registry at any time (used by the transitional reconciler anyway, §6 stage 1) — but with **new ids**, so stage 5 ships only after ≥2 weeks of stage-4 bake with a verification query (`SELECT count(*) FROM tool_results WHERE tool_key IS NULL`, jsonb arrays scanned for unresolvable keys) returning zero.
- Referential integrity for `custom:` keys moves to the app layer: custom tools are soft-deleted (unchanged), so keys keep resolving for history display; hard deletes were never exposed. `ToolKey.resolve` returning nil is an explicit, tested code path (skip at assembly, method_not_found at call).

---

## 5. MCP serving path

### 5.1 Swap actionmcp → official `mcp` gem (committed choice)

Rationale (from the research): the current monkey-patch already *simulates* the official gem's documented Rails idiom — server-per-request with a computed `tools:` array, stateless Streamable HTTP; staying on actionmcp means rewriting the patch against 7 versions of internal churn (5-arg `send_tools_call`, pagination, tasks, consent bypass) *and keeping a patch forever*, since it has no resolver extension point for DB tools through 0.111.1. The official gem needs **no internals overridden**, supports protocol versions 2024-11-05…2025-11-25 (wider than actionmcp 0.111's dropped 2025-03-26), is the most actively maintained, and its `MCP::Tool.define` is exactly how DB-built custom tools enter the list. Fleetio's production write-up is the shipping template. Aixle's per-request `mcp_key` auth is precisely the 2026-07-28 "list MAY vary by authorization presented on the request" blessed pattern.

```ruby
# Gemfile: gem "mcp", "~> 0.22"        (removes gem "actionmcp")

# config/routes.rb
post "/mcp",        to: "mcp/server#handle"
post "/action_mcp", to: "mcp/server#handle"   # transitional alias for in-flight agent containers

# app/controllers/mcp/server_controller.rb
class Mcp::ServerController < ActionController::API
  def handle
    session = TerminalSession.active.find_by(mcp_key: bearer_token)
    return head :unauthorized unless session

    ctx = Tools::Context.for_session(session, surface: :mcp_list)
    entries = Toolset.for_session(session, ctx) + Toolset.managed_aliases(session)

    server = MCP::Server.new(
      name: "aixle", version: Aixle::VERSION,
      tools: entries.map { |e| e.to_mcp_tool },
      server_context: { session: session, ctx: ctx }
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    result = transport.handle_request(request)
    render json: result[:body], status: result[:status]  # exact shape per gem 0.22 API
  end

  private
  def bearer_token = request.headers["Authorization"]&.delete_prefix("Bearer ")
end
```

Deleted: `config/initializers/action_mcp_dynamic_tools.rb` (the whole patch), `app/mcp/application_gateway.rb`, the engine mount, actionmcp's session tables. The abstract `app/mcp/tools/application_mcp_tool.rb` etc. are removed (never used).

### 5.2 Entry → wire adapter (one path for both sources)

```ruby
# on the duck type
def to_mcp_tool
  entry = self
  MCP::Tool.define(
    name: wire_name,
    description: description,
    input_schema: input_schema,
    annotations: entry.annotations  # MCP::Tool::Annotations
  ) do |args, server_context|
    entry.mcp_call(args, server_context[:ctx])
  end
end

def mcp_call(args, ctx)
  call_ctx = ctx.with(surface: :mcp_call)
  unless available?(call_ctx)   # enforce — hiding is not authorization
    return MCP::Tool::Response.new([{ type: "text", text: unavailable_reason(call_ctx) }], error: true)
  end

  args = ArgResolution.resolve_repository_params(args, call_ctx.session)  # extracted from the old patch, unchanged

  if execution_mode == :container
    tr = ToolResult.create!(tool_key: key, custom_tool_id: custom? ? row.id : nil,
                            terminal_session: call_ctx.session, step_run: call_ctx.session.step_run,
                            execution_id: ToolResult.generate_id, state: "processing")
    dispatch_temporal(args, call_ctx, tool_result: tr)   # CustomToolStrategy / container_definition
    MCP::Tool::Response.new([{ type: "text", text:
      "Started. execution_id=#{tr.execution_id}. Poll with read_tool_result(tool_result_id: \"#{tr.execution_id}\"); " \
      "first check in ~10s." }])                          # echo id + poll hint (research hardening)
  else
    result = new(args: args, context: call_ctx).call     # platform in-process
    to_response(result)                                   # exit_code 0 → text; else error content
  end
end
```

Sync platform tools also get a `ToolResult` row *optionally* later (audit trail) — not required by this design; `tool_key` supports it when wanted. `read_tool_result` keeps its execution_id contract untouched — the research confirms polling is the only interop-safe async mechanism in mid-2026 and spec Tasks are a moving target (SEP-2663); we deliberately do **not** adopt MCP tasks now, and losing actionmcp's broken tasks implementation costs nothing.

Custom-tool `_meta` ships tags: `"_meta": {"ai.aixle/tags": ["custom"], "ai.aixle/key": "custom:42"}`; platform tools ship their domain tags the same way (reverse-DNS-prefixed per spec; never under `mcp`/`modelcontextprotocol`).

### 5.3 Managed MCP servers / Coder namespacing — preserved

The `mcp__<server-name>__<tool>` aliasing survives as a pure decorator, so multiple Coder integrations in one scope still surface independently:

```ruby
class ManagedAlias < SimpleDelegator
  def initialize(entry, mcp_server) = (@server = mcp_server; super(entry))
  def wire_name = "mcp__#{@server.name}__#{__getobj__.wire_name}"
  def mcp_call(args, ctx) = __getobj__.mcp_call(args, ctx.with(mcp_server: @server))
end
```

Because every alias is materialized into the per-request `tools:` array, no name-parsing dispatch is needed — the old `parse_managed_namespace` logic disappears; the handler receives `ctx.mcp_server` for per-integration resolution exactly as `mcp_server:` flows into handlers today. `MCPServer` model rows (internal/custom/managed) are untouched — they are session configuration for agent containers, orthogonal to this registry.

---

## 6. Migration outline — ordered, independently shippable stages

**Stage 0 — Port + parity (no behavior change).** Write all ~52 `PlatformTool` classes (mechanical: seed entry supplies DSL metadata, `InternalTools::*#execute` body becomes `#call`). Old code paths stay live. Ship a **golden parity spec**: for every seeded row, assert registry entry exists with identical name/description/schema/execution_mode, and vice versa. Add `tools:check` CI task (registry key uniqueness, spec-regex names, JSON-Schema meta-validation, no `mcp__` prefixes).

**Stage 1 — Registry becomes the single source of truth (kills drift on day one).** Replace `Seeds::PlatformTools.seed!` with `PlatformToolRegistry.reconcile!` — the Solid Queue `persist_static_tasks` pattern: upsert rows *from the registry* by `(name, kind)`, prune platform rows whose key vanished, run on deploy where the seed rake ran. Delete `db/seeds/platform_tools.rb` (783 lines). Point `InternalToolExecutor` dispatch at `PlatformToolRegistry.fetch(tool.name).new(...).call`. From here, adding a platform tool = **one file**; the row appears automatically. Ships alone; FKs, serving, pickers untouched.

**Stage 2 — Unified availability + taxonomy readers.** Introduce `Tools::Context`/`IntegrationSet`/`Toolset`. `TerminalSession#available_tools` delegates to `Toolset.for_session` (injection via tags). Pickers move to `Toolset.pickable`; Builder moves to the `surface: :builder` tag query (fixing the kind-mismatch bug). Wire `available?` into the *existing* actionmcp patch's list/call methods (few lines). Delete `ManagedMCPToolRegistry` and in-handler presence checks. Behavior change to announce: integration-gated tools are now hidden at runtime, not error-at-call.

**Stage 3 — Serving swap.** Add `mcp` gem, `Mcp::ServerController`, alias route; remove actionmcp, the initializer patch, gateway, engine mount. Depends only on Stage 2. Container strategies' agent MCP endpoint config flips to `/mcp`; the alias route carries in-flight sessions.

**Stage 4 — String keys.** Schema steps 1–4 from §4.2: add key columns, dual-write, backfill, flip readers (SessionConfigResolver builds key arrays; FE pickers submit keys; Typelizer resources regenerate). Rollback = flip readers back.

**Stage 5 — Destructive cleanup (after ≥2 weeks bake + verification queries).** Schema step 5: delete platform rows, drop `session_tools`/old id arrays/`kind`/`requires_integration`, rename `tool_id`→`custom_tool_id`, rename `tools`→`custom_tools`, delete `InternalToolExecutor`, `InternalTools::*`, `reconcile!` itself, and the parity spec. End state reached: no rows, no seeds, no reconciler, no drift to check.

Stages 0–1 alone already deliver the headline goal ("wrote the class, forgot the seed" impossible); 2 unifies gating; 3 modernizes serving; 4–5 complete the DB story. Each stage is a separate green-`check_all` deploy.

---

## 7. Trade-offs, named honestly

- **Two object shapes behind one duck type.** Admin (Administrate dashboards, Ransack) loses platform rows to query — replace with a registry-backed admin page. Anything doing `Tool.find(id)` for platform tools must move to keys; the grep surface is real but bounded (Stage 4 flips it).
- **App-layer referential integrity for `custom:` keys.** Orphaned keys error visibly at resolution instead of being FK-impossible. Soft-delete semantics (already the norm here) make this mostly theoretical; it is the price every string-key system in the research pays.
- **No server push.** Stateless transport forfeits `list_changed`; per-request recompute + actionable call errors is the ecosystem-verified compensation. If push ever matters, it returns as an SSE side-channel, not as connection state.
- **Behavior change in gating.** Hiding unavailable tools changes agent-visible surface vs today's error-at-call for `slack_post_message` in workflow sessions; workflow prompts that name the tool must tolerate absence (the call-time remedy still covers stale lists).
- **`mcp` gem is young.** 0.22.x API (`handle_request` return shape, `Tool::Response` error kwarg) must be pinned and verified at Stage 3; it is Shopify+MCP-org maintained and the most active option, but churn risk is nonzero — mitigated by the fact that our surface area is ~1 controller + 1 adapter method.
- **Renaming `tools`→`custom_tools` is cosmetic churn** with real conceptual payoff (the table name states the invariant). It is isolated in Stage 5 and can be dropped from scope without weakening the rest.
- **`available` lambda blocks are code, not data** — they cannot be edited by ops at runtime. That is intentional (Flipper is the runtime-policy layer); the closed `inject` enum similarly trades flexibility for auditability.
