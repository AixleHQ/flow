# Technical Design — #302 Copy workflow dependencies (agents, skills, mcp) when adding from catalog

## 1. Problem & Goal

When a user adds a workflow from the company catalog into a project, only the
`Workflow` row (plus its `Step`/`SubStep` children) is copied. The agents,
skills, MCP servers, and custom tools the workflow depends on are **not** copied —
they stay as shared **Company-scoped** resources, and the new Project-scoped
workflow keeps pointing at them by raw ID.

Two concrete problems follow from that:

1. **No per-project customization.** A team cannot tweak an agent persona, a
   skill, or an MCP server for their project without editing the shared
   Company resource, which affects every other project/workflow that references it.
2. **Silent breakage.** If the shared Company resource is later edited or
   deleted, the copied workflow's behavior changes (or breaks) out from under
   the team. The dependency is a dangling cross-scope pointer — see the runtime
   resolution analysis in §2.4.

**Goal:** when a workflow is copied from catalog into a project, automatically
bring along the agents, skills, MCP servers, and custom tools it references, as
**Project-local copies** that the team can freely configure. Secrets/credentials
live exclusively in `ConfigItem` rows (encrypted, scoped), and those rows are
**never** copied — the project team provides their own. MCP `env`/`headers` are
copied as-is (they are user-entered config that references secrets by name via
`config_item:NAME`, not a secrets store themselves — see §2.5/D3), and managed-MCP
/ integration-gated resources are passed through or gated rather than duplicated
(D4/D9). The secrets boundary is the `ConfigItem` row, not the `env`/`headers` jsonb.

## 2. Current State

### 2.1 Catalog → project copy entry points

Two controllers both call the same service to copy a workflow:

- `app/controllers/web/company/workflow_catalog_controller.rb:17-27` —
  `#duplicate` looks up a published company workflow and a target project, then
  `WorkflowDuplicator.new(workflow, target_scope: project).duplicate!` and
  redirects to the builder. This is the **catalog → project** path the issue is about.
- `app/controllers/web/company/projects/workflows_controller.rb:99-103` —
  `#duplicate` is the in-project "Duplicate" action, also via
  `WorkflowDuplicator.new(source, target_scope: current_project)`.

Authorization for the catalog path: `app/policies/web/company/workflow_catalog_policy.rb:6-7`
(`index?`/`duplicate?` = `company_member?`). Routes:
`config/routes.rb:255` (`post :duplicate` member on `workflow_catalog`) and
`config/routes.rb:221` (`post :duplicate` member on project `workflows`).

### 2.2 The duplicator copies references, not resources

`app/services/workflow_duplicator.rb` is the whole copy mechanism:

- `app/services/workflow_duplicator.rb:12-16` — creates the new workflow with
  `config: @source.config.deep_dup`. The workflow `config` carries
  `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`
  (the whitelist is `Workflow::ALLOWED_CONFIG_KEYS`,
  `app/models/workflow.rb:15-18`). These **resource ID arrays are copied verbatim**.
- `app/services/workflow_duplicator.rb:50-72` — `duplicate_step` copies each
  step including `agent_id` (a real FK), and the JSONB arrays `tool_ids`,
  `mcp_server_ids`, `skill_ids`, `asset_ids` — again **verbatim**.
- Only `depends_on_step_ids` is remapped (`workflow_duplicator.rb:18-32`) via a
  `step_id_map`. There is no equivalent map for agents/skills/mcp/tools.

So after a catalog copy, the new Project workflow's steps still reference the
**source Company's** `Agent`/`Skill`/`MCPServer`/`Tool` IDs.

### 2.3 Data model of the four dependency types

How a `Step` references its dependencies (`db/schema.rb` `steps` table; model
`app/models/step.rb`):

- `agent_id` — bigint FK → `agents` (`step.rb:7`, `belongs_to :agent, optional: true`).
- `tool_ids`, `mcp_server_ids`, `skill_ids`, `asset_ids` — JSONB arrays of bare IDs,
  **not** FKs. In `db/schema.rb` the `steps` table declares each as
  `jsonb default: [], null: false`. The `null: false` is load-bearing for this work:
  every `map_*` mapper for an array column **must return an array, never nil**
  (the §4 sketch already returns arrays via `filter_map`/`map`, so this holds — but
  a mapper that ever returned nil would violate the NOT NULL constraint and abort
  the copy transaction). `agent_id` is nullable, so `map_agent_id(nil)` returning
  `nil` is fine.

Each dependency model is **polymorphically scoped** (`scope_type` in
`Company`/`Project`/`System`) with a `visible_for_project` scope that unions the
project's own rows with its company's rows:

- **Agent** — `app/models/agent.rb:8-43`. Scope `Company`/`Project`/`System`.
  `name` unique per scope (`agent.rb:25`, plus DB unique index
  `index_agents_on_scope_type_and_scope_id_and_name`). Persona fields only
  (`persona`, `communication_style`, `principles`, `title`, `icon`) — **no
  secrets**. `source` is `custom`/`bmad_import`.
- **Skill** — `app/models/skill.rb:13-32`. Scope `Company`/`Project` (no System).
  `name` unique per scope (`skill.rb:18`). Registry-backed: `package`, `source`,
  `source_url`, `content` (SKILL.md), `references_data`. **No secrets** — actual
  install is `npx skills add` at session start.
- **MCPServer** — `app/models/mcp_server.rb:14-64`. `kind` =
  `internal`/`custom`/`managed`. `internal` is system-provided (no scope).
  `custom` is Company/Project scoped. `managed` is auto-provisioned by an
  `Integration` (`mcp_server.rb:39-41`, FK-cascade lifecycle) — credential-bearing.
  `name` unique per scope (`mcp_server.rb:34`). Columns `env` (jsonb),
  `headers` (jsonb) **can carry secret material** (e.g. `Authorization` header).
- **Tool** — `app/models/tool.rb:18-67`. `kind` =
  `custom`/`system`/`internal`/`workflow`/`meta`. Only `custom` is
  Company/Project scoped; `system`/`internal`/`workflow` are platform tools
  (`platform_tool?`, `tool.rb:116-118`), `meta` is hidden. `name` unique per
  scope among non-deleted (`tool.rb:37-38`). Has `tool_files` (script content,
  `tool.rb:26`) and `required_config_items` (names of `ConfigItem`s, jsonb).
  Soft-deleted via `deleted_at`.

The issue names "agents, skills, mcp." **Custom tools** (`tool_ids`) are the
same class of problem — a Company custom tool referenced by a copied step is
just as shared/fragile. This design treats custom tools the same way; see the
OPEN QUESTION in §5 on whether tools are in scope for the first cut.

### 2.4 Why the dangling pointer "works" today and why it's fragile

At session-build time, `app/services/session_config_resolver.rb` resolves the
effective resource sets for a workflow step **without re-scoping the IDs to the
session's project**:

- `resolve_configured_agent_id` → `step.agent_id` directly (`:95-99`).
- `resolve_tool_ids`/`resolve_skill_ids`/`resolve_mcp_server_ids` →
  `workflow.base_*_ids + step.*_ids` (`:114-142`), no `visible_for_project` filter.
- The IDs are later loaded via `SessionService#scoped_resources`
  (`app/services/session_service.rb:133-135`).

Because a catalog copy lands in a project **inside the same company**, the
referenced Company resources are still `visible_for_project` for that project, so
the copied workflow keeps running — but every project that copied the same
catalog workflow shares one Company `Agent`/`Skill`/`MCPServer`. Editing it for
one team changes it for all; deleting it breaks all. That is exactly #302.

### 2.5 ConfigItem / secret model (what must NOT be copied)

- `app/models/config_item.rb` — `name` (upcased), `item_type`
  `secret`/`variable`, encrypted `encrypted_value` for secrets. Scoped
  Company/Project. Resolved at runtime by name via
  `ConfigItem.effective_for_project` (`config_item.rb:47-53`) and referenced as
  `config_item:NAME` strings inside MCP `env`/`headers`
  (resolved by `session_context_service.rb:316-344`:
  `resolve_config_item_reference` for whole-value refs, `resolve_embedded_references`
  for refs embedded in a string like `"Bearer config_item:KEY"`) and Tool
  `required_config_items` (`app/services/container_strategies/custom_tool_strategy.rb:72-85`).
  Grep across `app/` confirms `session_context_service.rb:316-344` is the **only**
  producer/consumer of `config_item:` strings — there is no other code, and **no
  secret/non-secret discriminator on `env`/`headers` values** anywhere.
- **The `env`/`headers` columns are NOT a "secrets" column.** The MCP server form
  permits arbitrary freeform `env: {}` and `headers: {}`
  (`mcp_servers_controller.rb:47-52`) with no validation; teams routinely store
  **non-secret literals** there (public base URLs, model names, feature flags,
  non-sensitive header values), interspersed with `config_item:NAME` references for
  the sensitive bits. A heuristic that treats "any value that is not a
  `config_item:` reference" as a secret to scrub would be wrong and lossy — it would
  delete legitimate non-secret config and break the copied server. There is no
  grounded way to tell a literal secret from a literal non-secret here.
- Implication for the copy: the actual *secrets* live in `ConfigItem` rows
  (encrypted, scoped), referenced by name. **We never copy `ConfigItem` rows** — that
  is the secrets boundary. The `env`/`headers` jsonb is user-entered project config
  and is copied **verbatim**; because a catalog copy lands in a project **inside the
  same company**, every `config_item:NAME` reference it contains still resolves via
  `ConfigItem.effective_for_project` for the target project (if the target company
  has that item) exactly as it did for the source. See D3.

### 2.6 Frontend today

- Catalog page `app/frontend/pages/Company/WorkflowCatalog/IndexPage.tsx:48-62`
  posts to `/company/workflow_catalog/:id/duplicate` with `project_id` and on
  success the server redirects to the builder.
- Builder `app/frontend/pages/Projects/Workflows/BuilderPage.tsx` loads the
  per-step pickers from **deferred** props that are already scoped
  `visible_for_project`: `agents`, `tools`, `skills`, `mcp_servers` come from
  `Web::Company::Projects::Workflows#builder`
  (`app/controllers/web/company/projects/workflows_controller.rb:42-53`). The
  step pickers bind `agentId`/`toolIds`/`mcpServerIds`/`skillIds`
  (`BuilderPage.tsx:1093-1095, 1236-1259`).
- Generated types `app/frontend/types/generated/Step.ts` already type these as
  `number`/`Array<number>`. **No serialized shape changes** are introduced by
  this work, so no Typelizer regeneration is required.

**Key FE consequence:** if the backend remaps the copied step/workflow IDs to
the new Project-local copies, the builder pickers display the project-local
resources automatically. The frontend needs essentially no functional change.

## 3. Proposed Design

**Approach: deep-copy dependencies inside `WorkflowDuplicator`, building ID
remap maps per resource type, in a single transaction.**

When `@target_scope` is a `Project`, before/while copying steps:

1. Collect the distinct dependency IDs the source workflow uses, across **both**
   the workflow `config.base_*_ids` and every step's `agent_id` / `tool_ids` /
   `skill_ids` / `mcp_server_ids` (and custom `tool_ids`).
2. For each referenced **Agent/Skill/MCPServer/custom-Tool** that is **not
   already visible in the target project as a project-local row**, create a
   Project-scoped copy and record `source_id → new_id` in a per-type map.
3. Apply the maps when writing step columns and the workflow `config`, so the
   copy references project-local resources.

Resources that are **platform-provided / shared by design** are passed through
unchanged (their IDs are stable and project-agnostic):

- `MCPServer` with `kind: internal` (no scope) — keep ID as-is.
- `MCPServer` with `kind: managed` — **do not deep-copy** (it is owned by an
  `Integration` via FK cascade, `mcp_server.rb:39-41`; the project cannot own a
  detached copy). But **do not blindly drop the reference either** — pass the ID
  through unchanged **if the managed server is still `visible_for_project` in the
  target**, and drop it only if it is not. `visible_for_project`
  (`mcp_server.rb:56-60`) includes ANY enabled `custom` OR `managed` server scoped
  to the target's company (`scope_type: "Company", scope_id: project.company_id`)
  or to the target project — kind is **not** filtered on those two branches.
  Since catalog copies are same-company and managed MCPs can be company-wide
  (`integrations.project_id` is nullable, `company_id` non-null, `db/schema.rb`),
  a company-scoped managed MCP referenced by the source **stays visible in the
  target and works today**; dropping it would break a working dependency. See D4.
- `Tool` with `kind` in `system`/`internal`/`workflow`/`meta` (`platform_tool?`)
  — keep ID as-is.
- `Agent` with `scope_type: System` — keep ID as-is.
- A dependency that is **already Project-scoped to the target project**
  (in-project duplicate case) — keep ID as-is.

Idempotency / de-dup within a project: a dependency `name` is unique per scope.
If a same-named project-local resource already exists (e.g. the team copied two
catalog workflows that share an agent, or copied the same workflow twice), the
copier **reuses the existing project-local row** rather than failing the unique
constraint. This makes repeated catalog copies converge instead of erroring.

### Rationale

- **Mirror the one existing copy pattern.** `WorkflowDuplicator` already owns
  "copy a workflow graph and remap IDs in a transaction"
  (`workflow_duplicator.rb:10-36` does this for `depends_on_step_ids`). Extending
  the same service with more remap maps is the smallest, most consistent change,
  and it automatically covers **both** copy entry points (catalog and in-project)
  with one implementation.
- **No schema change to the hot path.** Steps keep storing `number[]` ID arrays;
  we just write *different* (project-local) IDs. No new columns, no resolver
  changes, no Typelizer regeneration.
- **Same-company scope keeps it simple.** Catalog copies are always within one
  company (`Workflow.published_in_company`, `workflow.rb:28`), and the target
  project belongs to that company, so every source dependency is readable when
  copying. No cross-company ACL problem.
- **`inherit_all_project_resources` interaction (considered, no change needed).**
  When `workflow.config.inherit_all_project_resources` is true,
  `session_config_resolver.rb:118/128/138` unions the **project's own**
  `project_tool_ids`/`project_skill_ids`/`project_mcp_server_ids` into the effective
  set at runtime. After a catalog copy the workflow lands in the target project, so
  it will inherit the **target project's** resource set (a different set than the
  source's). This is the desired behavior — the copy should reflect the project it
  now lives in — and it is independent of the explicit base/step IDs we remap. The
  `remapped_config` sketch (§4) deliberately leaves this boolean untouched.

### Rejected alternatives

- **A) Resolve-time re-scoping instead of copying.** Make
  `SessionConfigResolver` map shared IDs to project-local equivalents on the
  fly. Rejected: does not satisfy the issue's core requirement ("ready to use or
  customize... already available in that project") — there would be nothing to
  customize in the project, and it adds hidden indirection to a hot path.
- **B) Copy *all* company resources into the project on copy.** Rejected:
  over-copies unrelated resources, pollutes the project, and risks name
  collisions for resources the workflow doesn't use.
- **C) New `WorkflowDependencyCopier` service called from the controllers,
  separate from `WorkflowDuplicator`.** Rejected: it would need to re-open the
  same transaction and re-walk the same steps the duplicator just wrote, and
  would duplicate the remap bookkeeping. Folding it into the duplicator (with a
  small private collaborator class, see §4) keeps one transaction and one source
  of truth. (We *do* extract a private `DependencyCopier` helper inside the
  service for readability, but it is not a separately-invoked service.)
- **D) Add real FK join tables for step→tool/skill/mcp.** Out of scope; large
  migration touching the resolver, resources, and FE. The JSONB arrays remain.

## 4. Detailed Changes

### Backend

#### `app/services/workflow_duplicator.rb` (primary change)

Extend the service to remap dependencies when the target is a `Project`. Sketch:

```ruby
class WorkflowDuplicator
  # platform / shared resources we never copy — IDs are stable across projects
  def duplicate!
    ActiveRecord::Base.transaction do
      @dep_copier = DependencyCopier.new(source: @source, target_project: target_project)

      new_workflow = @target_scope.workflows.create!(
        name: available_name,
        description: @source.description,
        config: remapped_config(@source.config.deep_dup)
      )

      step_id_map = {}
      step_pairs  = []
      @source.steps.not_deleted.order(:position).each do |step|
        new_step = duplicate_step(step, new_workflow)
        step_id_map[step.id] = new_step.id
        step_pairs << [step, new_step]
      end

      step_pairs.each do |source_step, new_step|
        next if source_step.depends_on_step_ids.blank?
        remapped = source_step.depends_on_step_ids.filter_map { |old| step_id_map[old] }
        new_step.update!(depends_on_step_ids: remapped)
      end

      new_workflow
    end
  end

  private

  # nil unless we're copying into a Project (in-company duplicate / catalog copy)
  def target_project
    @target_scope if @target_scope.is_a?(Project)
  end

  def remapped_config(config)
    return config unless target_project
    config["base_tool_ids"]       = @dep_copier.map_tool_ids(config["base_tool_ids"])             if config["base_tool_ids"]
    config["base_skill_ids"]      = @dep_copier.map_skill_ids(config["base_skill_ids"])           if config["base_skill_ids"]
    config["base_mcp_server_ids"] = @dep_copier.map_mcp_server_ids(config["base_mcp_server_ids"]) if config["base_mcp_server_ids"]
    # base_asset_ids intentionally NOT remapped — assets are out of scope (D5)
    config
  end

  def duplicate_step(step, workflow)
    new_step = workflow.steps.create!(
      # ...unchanged scalar columns (name, description, instructions, position, ...)
      agent_id:       @dep_copier.map_agent_id(step.agent_id),
      tool_ids:       @dep_copier.map_tool_ids(step.tool_ids),
      mcp_server_ids: @dep_copier.map_mcp_server_ids(step.mcp_server_ids),
      skill_ids:      @dep_copier.map_skill_ids(step.skill_ids),
      asset_ids:      step.asset_ids,          # unchanged (D5)
      depends_on_step_ids: []
    )
    # ...sub_steps copy unchanged...
    new_step
  end
end
```

When `target_project` is `nil` (e.g. duplicating to a `Company` scope, which the
`#publish`/seed paths can do), `map_*` are identity functions, preserving today's
behavior exactly.

#### New private collaborator: `WorkflowDuplicator::DependencyCopier`

Same file (or `app/services/workflow_duplicator/dependency_copier.rb`). One
method per resource type; each memoizes a `source_id → project_local_id` map and
copies on first use. Sketch for agents (skills/mcp/tools mirror it):

```ruby
class WorkflowDuplicator
  class DependencyCopier
    def initialize(source:, target_project:)
      @project = target_project
    end

    def map_agent_id(id)
      return id if id.nil?
      agent_map.fetch(id, id) # unknown/cross-company → leave as-is (defensive)
    end

    private

    def agent_map
      @agent_map ||= {}
    end

    def copy_agent(agent)
      return agent.id if agent.system?                              # System → shared
      return agent.id if agent.scope_type == "Project" && agent.scope_id == @project.id

      existing = @project.agents.find_by(name: agent.name)         # name unique per scope
      return existing.id if existing                               # idempotent reuse

      @project.agents.create!(
        name: agent.name, title: agent.title, icon: agent.icon,
        persona: agent.persona, communication_style: agent.communication_style,
        principles: agent.principles, source: agent.source
      ).id
    end
  end
end
```

Per-type copy rules (what to copy / skip / pass through):

- **Agent** — copy persona fields (`name`, `title`, `icon`, `persona`,
  `communication_style`, `principles`, `source`). Pass through `System` agents
  and already-project-local agents. No secrets exist on `Agent`.
- **Skill** — copy `name`, `title`, `description`, `package`, `source`,
  `source_url`, `content`, `references_data`. Reset `install_count` to 0. No
  secrets. (Could alternatively re-install via `SkillsRegistryService.install`
  using `package`, mirroring `skills_controller.rb:18` — but a direct row copy is
  offline-safe and preserves the exact `content`; see D6.)
- **MCPServer** — only deep-copy `kind: custom`. Copy `name`, `display_name`,
  `url`, `transport`, `description`, `command`, `args` (jsonb, `db/schema.rb`),
  `enabled`, **and `env`/`headers` verbatim** (D3). `env`/`headers` are user-entered project config, not a secrets
  column; `config_item:NAME` references in them stay resolvable in the same-company
  target, and non-`config_item:` entries are legitimate literals that must be
  preserved. Do **not** copy `integration_id` (custom servers have none; it is
  validated absent for non-managed, `mcp_server.rb:41`). Pass through `internal`
  (no scope) and `managed` IDs unchanged when the referenced server is still
  `visible_for_project` in the target; drop only if not visible (D4). The
  secrets boundary is solely "do not copy `ConfigItem` rows."
- **Tool** — only deep-copy `kind: custom`; pass through platform tools
  (`platform_tool?`, `tool.rb:116-118` → all non-`custom` kinds). Copy `name`,
  `display_name`, `description`, `docker_image`, `command`, `execution_mode`,
  `input_schema`, `required_config_items` (names only — the values are
  `ConfigItem`s the team supplies), `enabled`, **and `requires_integration`**
  (see decision D9 — copy it; the copied tool is correctly hidden from the target
  project's pickers until that integration is connected, consistent with
  secrets-not-copied; `visible_for_project` gates on it, `tool.rb:65-66`). Skip
  soft-deleted tools (`deleted_at` present, `tool.rb:45`).
  Copy `tool_files` as nested children — and here a text-only copy is **not
  enough**: `ToolFile` carries a Shrine `file` attachment
  (`tool_file.rb:7` `include ToolFileUploader::Attachment(:file)`) in addition to
  the legacy `content` column, and `db/schema.rb` `tool_files` has **both**
  `content` and `file_data`. Binary tool files (`tf.binary?` → `file.present?`)
  store their bytes in the Shrine `file`/`file_data`, not in `content`, and
  `custom_tool_strategy.rb:60-64` downloads `tf.file` for them at execution time.
  The copier **must replicate the Shrine `file` attachment for binary tool files**
  (e.g. copy `file_data` / re-upload the same `file`), not just the `content`
  column — otherwise every binary tool file is silently lost and the copied tool
  fails at runtime. For text-only tool files, copying `content` suffices.

Name-collision/idempotency: every `copy_*` does `find_by(name:)` in the project
first and reuses, so the per-scope unique indexes
(`index_agents_on_scope_type_and_scope_id_and_name`, etc.) are never violated and
repeated catalog copies converge. This `find_by`-then-reuse is reliable because
all four models override `name=` to downcase/sanitize before persisting
(`agent.rb:18-20`, `skill.rb:30-32`, `mcp_server.rb:27-29`, `tool.rb:30-32`): the
source row's `name` is already normalized, so `find_by(name: agent.name)` matches
the same normalized form in the target scope — there is no case/charset mismatch
that could defeat the de-dup. (Tool's unique index is additionally conditioned on
`deleted_at IS NULL`, `tool.rb:37-38`; since we skip soft-deleted source tools and
only ever create non-deleted copies, the `find_by` should likewise scope to
`not_deleted` to match the index.)

#### Controllers — `app/controllers/web/company/workflow_catalog_controller.rb`

Minimal/no change. The `#duplicate` action already calls the duplicator
(`:17-27`); the new behavior is internal to the service. Update the flash to
mention dependencies, e.g. `notice: "Workflow and its resources copied to #{project.name}"`.
Same optional copy-tweak for `Web::Company::Projects::WorkflowsController#duplicate`
(`workflows_controller.rb:99-103`).

#### Policies / Routes / Migrations

- **Policies:** none. `WorkflowCatalogPolicy` (`:6-7`) already gates on
  company membership; copying dependencies introduces no new authorization
  surface (everything stays within the same company, and the project membership
  is already enforced by `Project.for_user` in the controller, `:9`/`:19`).
- **Routes:** none.
- **Schema migration:** none. No new columns/tables; we write project-local IDs
  into the existing JSONB/FK columns.

### Frontend

- **No functional changes required.** Because the backend now remaps to
  project-local IDs, the builder's existing deferred pickers (`agents`, `tools`,
  `skills`, `mcp_servers` from `workflows_controller.rb:42-53`) already render the
  project-local copies, and the step pickers (`BuilderPage.tsx:1093-1095`,
  `:1236-1259`) bind the remapped IDs.
- **Optional UX copy:** in
  `app/frontend/pages/Company/WorkflowCatalog/IndexPage.tsx` change the modal
  helper text (`:139-141`) and/or button to communicate that agents, skills and
  MCP servers are copied too (e.g. "Agents, skills and MCP servers it uses are
  copied into the project. Secrets are not — add your own."). This is the only
  FE edit, and it is cosmetic.
- **Types:** no `@/types/generated` regeneration — no serialized field shapes
  change (`Step.ts`, `MCPServer.ts` etc. unchanged).

### Data migration (if any)

**None required for the feature.** New copies behave correctly going forward.

Optional **idempotent backfill** for already-copied Project workflows that still
point at Company resources (those created before this change). If product wants
existing copies repaired, add a `data migration` (or rake task) that, for each
active Project workflow, runs the same `DependencyCopier` over its steps/config
and rewrites IDs. It must be idempotent: the `find_by(name:)`-then-reuse logic
already makes re-running a no-op (a workflow whose steps already reference
project-local resources maps each ID to itself). Recommend gating this behind an
explicit decision (see OPEN QUESTION in §5) rather than auto-running, because
silently forking shared resources for existing projects changes behavior.

## 5. Edge Cases & Decisions

- **D1 — Dependencies live in two places.** Both `Step` columns *and*
  `workflow.config.base_*_ids` must be remapped. Verified consumers:
  `session_config_resolver.rb:114-142` (sums `workflow.base_*` + `step.*`).
  Decision: remap both.
- **D2 — Idempotent reuse by name.** If a project-local resource with the same
  `name` already exists, reuse it instead of creating a duplicate (per-scope
  unique indexes forbid duplicates anyway). This also dedupes within one copy
  when two steps share an agent.
- **D3 — MCP `env`/`headers` are copied VERBATIM; the secrets boundary is
  `ConfigItem`.** Earlier drafts proposed scrubbing "any value that is not a
  `config_item:` reference" as a literal secret. **Rejected** — it has no codebase
  grounding and is lossy. The form permits arbitrary freeform `env: {}`/`headers: {}`
  (`mcp_servers_controller.rb:47-52`) with no validation and no secret/non-secret
  discriminator; the only code that touches `config_item:` strings is
  `session_context_service.rb:316-344` (grep-confirmed sole consumer). Non-secret
  literals (public base URLs, model names, feature flags, non-sensitive header
  values) live in `env`/`headers` and the scrub rule would destroy them, breaking
  the copied server. **Decision:** copy `env`/`headers` verbatim. Actual secrets are
  in `ConfigItem` rows (encrypted, scoped), which we **never copy** — that is the
  secrets boundary. `config_item:NAME` references survive the copy and resolve in
  the same-company target via `ConfigItem.effective_for_project` (if the target
  company has that item), exactly as for the source. This still satisfies "secrets
  and credentials are not copied" because no `ConfigItem` value is ever duplicated.
  **Data-loss note:** if a team did paste a raw secret directly into `env`/`headers`
  (rather than using a `config_item:` reference), that raw value is copied along with
  everything else — but that pre-existing misuse is out of scope here, and there is
  no reliable way to detect it. The recommended migration path (steer users to
  `config_item:` references) is unaffected.
- **D4 — Managed MCP servers: pass through when still visible, drop only if not.**
  `kind: managed` servers are owned by an `Integration` via FK cascade
  (`mcp_server.rb:39-41`), so the project cannot own a detached deep-copy.
  **But the common same-company case keeps them working**: `visible_for_project`
  (`mcp_server.rb:56-60`) includes any enabled `custom` OR `managed` server scoped
  to the target's company or project — kind is **not** filtered on those branches
  (only `internal_servers` is kind-gated). A managed MCP can be company-wide
  (`integrations.project_id` nullable, `company_id` non-null, `db/schema.rb`), and
  catalog copies are same-company by construction, so a referenced company-scoped
  managed MCP is **still `visible_for_project` in the target and works today**.
  **Decision:** do not deep-copy a managed server; **pass its ID through unchanged
  if it remains `visible_for_project(target_project)`**, and drop the reference only
  when it is not visible (e.g. a source-project-scoped managed server that does not
  belong to the target). Earlier "always drop the reference" would have broken a
  currently-working dependency. Do not copy `integration_id`. Surfacing a
  "needs setup" warning when a reference is dropped is an OPEN QUESTION (Q3).
- **D5 — Assets are out of scope.** The issue lists "agents, skills, mcp."
  `asset_ids` / `base_asset_ids` reference `Asset` (project files), which are a
  different concern (storage, versions) and not "dependencies the workflow needs
  to run." Decision: do **not** copy assets; leave `asset_ids` as-is. (Today they
  already point at source-project assets; unchanged behavior.)
- **D6 — Skill copy vs re-install.** Direct row copy preserves exact `content`
  and is offline-safe; re-install via `SkillsRegistryService` (mirroring
  `skills_controller.rb:18`) re-fetches from the registry. Decision: direct row
  copy for determinism; re-install is a later enhancement. **Model nuance:**
  unlike Agent/MCPServer/Tool, `Skill#scope` is **not** `optional: true`
  (`skill.rb:14` `belongs_to :scope, polymorphic: true`) and the model requires
  `validates :content, presence: true` (`skill.rb:21`) even though the column is
  nullable in the schema. The direct-row-copy approach handles both: it always
  sets `scope` to the target project and copies `content` verbatim. (If the
  re-install alternative were ever adopted, it would have to guarantee `content` is
  populated before `create!`, since a registry fetch returning empty content would
  fail the presence validation.)
- **D7 — Platform/System pass-through.** System agents, internal/system/workflow
  tools, and internal MCP servers are shared-by-design and keep their IDs.
- **D8 — Cross-company defensiveness.** Catalog copies are same-company by
  construction, but `map_*` leaves any unknown/unreadable ID unchanged rather
  than raising, so a stray ID can never abort the whole copy. The `copy_agent`
  guard (`agent.scope_type == "Project" && agent.scope_id == @project.id`, §4
  line ~330) detects an already-target-local agent. A Company-scoped agent from a
  **different** company (only reachable via a malformed in-project duplicate of a
  System/foreign workflow, never via the same-company catalog path) is not
  explicitly handled — it falls through to `agent_map.fetch(id, id)` and the ID is
  **left as-is rather than raising**. This is intentionally tolerated: a dangling
  cross-company ID is preferable to aborting the whole copy, and the catalog path
  cannot produce one. Same tolerance applies to skill/mcp/tool mappers.
- **D9 — `requires_integration` on copied custom tools.** `Tool#visible_for_project`
  filters on `tools.requires_integration IS NULL OR ... IN
  (active_integration_providers(project))` (`tool.rb:65-66`). A copied custom tool
  that carries a `requires_integration` provider (real column, `db/schema.rb`
  `tools`) will be **invisible in the target project's builder pickers until that
  integration is connected**. Decision: **copy `requires_integration` as-is** (do
  not null it). This is consistent with the secrets-not-copied stance — the row is
  copied, but the team must connect the same integration to make it usable, exactly
  as they must supply their own `ConfigItem` secrets. This interacts with the
  acceptance criterion "all required ... already available ... without any manual
  setup": such a tool is *present* in the project but *gated* until the integration
  is connected (the same gating it has in the source company). Surfacing this in the
  builder is folded into Q3.

### OPEN QUESTIONS (need PRODUCT input)

- **Q1 — Are custom *tools* in scope for v1?** The issue title says "agents,
  skills, mcp" but custom tools (`tool_ids`) have the identical sharing/fragility
  problem. Recommend yes; confirm.
- **Q2 — Backfill existing copied workflows?** Should we repair Project
  workflows already copied before this change (forking their shared resources
  into project-local copies), or only fix new copies going forward?
- **Q3 — Missing-dependency UX.** Three cases can leave a copied workflow with a
  dependency that needs the team's attention: a managed MCP reference that was
  dropped because it is not `visible_for_project` in the target (D4); a custom tool
  hidden from pickers because its `requires_integration` is not connected (D9); and a
  `config_item:NAME` reference in copied `env`/`headers` whose `ConfigItem` the
  target company does not yet have. Current proposal handles all three silently
  (drop / gate / leave-unresolved). Should we instead surface a "needs setup" banner
  in the builder listing what to connect or add? The latter is additional FE work.
- **Q4 — Should the copy be opt-in?** Always copy dependencies (proposed), or
  give the user a "copy dependencies" checkbox in the duplicate modal?

## 6. Acceptance Criteria Mapping

| Acceptance criterion (from issue) | Change that satisfies it |
| --- | --- |
| "automatically bring along the agents, skills, and MCP servers it needs — as project-local copies" | `WorkflowDuplicator::DependencyCopier` copies Agent/Skill/custom-Tool/MCPServer as Project-scoped rows and remaps step + `config` IDs (§4 `workflow_duplicator.rb`). |
| "the team can freely configure" without affecting everyone else | Copies are `scope_type: "Project", scope_id: project.id`; editing them no longer touches the Company originals (D7, D2). |
| "Secrets and credentials are not copied: the project team provides their own." | `ConfigItem` rows are **never** copied — that is the entire secrets boundary (D3). MCP `env`/`headers` are copied verbatim (they are user config, not secrets); their `config_item:NAME` references resolve in the same-company target and supply no secret material themselves. Managed MCP servers are not deep-copied (D4). Custom tools carry `requires_integration` but no secret values (D9). |
| "opens it in the builder, and all required agents, skills and MCPs are already available... without any manual setup" | After remap, the builder's existing `visible_for_project` pickers and remapped step IDs show the project-local copies with no FE change (§2.6, §4 Frontend). Controller still redirects to the builder (`workflow_catalog_controller.rb:23`). **Caveat:** a copied custom tool with `requires_integration` is present but hidden from pickers until that integration is connected (D9), and a managed MCP reference is kept only while it stays `visible_for_project` (D4) — both consistent with "the team provides their own credentials/integrations." |
| "the workflow may [no longer] silently break if those shared resources change or are removed" | The copied workflow references only project-owned rows; resolver (`session_config_resolver.rb:114-142`) now sees stable project-local IDs (§2.4). |

## 7. Test Plan

### Service tests — `test/services/workflow_duplicator_test.rb` (extend)

**Important — the existing tests do NOT actually exercise copying, and most will
NOT need changing.** Only the **first** test (`:22-40`) asserts verbatim arrays
(`assert_equal [7], copied_steps[0].tool_ids`, plus `[8]`/`[9]`/`[42,43]`). The IDs
`7`/`8`/`9` are **phantom** — the setup (`:11-13`) never creates `Tool`/`Skill`/
`MCPServer` rows with those IDs. Under the defensive `map_*` design
(`agent_map.fetch(id, id)` → unknown ID left as-is, §4/D8), every one of those
phantom IDs maps to itself, so **those assertions still pass unmodified**. The tests
at `:42-62` are pure name-uniqueness tests with no resource-ID assertions and are
unaffected. There is also currently **zero coverage of the `agent_id` FK path** —
no existing test sets or asserts `step.agent_id`, even though it is the column this
change touches most.

So the real work is not "update assertions" but "**rewrite the test setup to seed
REAL company-scoped resources**" so copying is actually exercised. Replace the
phantom IDs with real `Agent`/`Skill`/`MCPServer`/`Tool` rows scoped to `@company`,
set `step.agent_id` to a real company agent, and then add:

- Copies a Company `Agent` referenced by `step.agent_id` into the target project
  and points the new step at the **new** agent (`scope_type == "Project"`,
  `scope_id == project.id`, **different id** from the source agent); persona fields
  preserved.
- Copies Company `Skill`/`MCPServer`/custom `Tool` referenced by
  `step.skill_ids`/`mcp_server_ids`/`tool_ids` and remaps the arrays to the new
  project-local IDs (assert the arrays changed, and each new row is
  `scope_id == project.id`).
- Remaps `config.base_tool_ids`/`base_skill_ids`/`base_mcp_server_ids`; assert the
  remapped arrays are **never nil** (the `steps`/config arrays are `null: false`).
- **Idempotent reuse:** two steps referencing the same agent produce **one**
  project-local agent; running the duplicator twice doesn't create duplicates
  and doesn't raise the per-scope unique-name constraint (relies on name
  normalization, §4 / D2).
- **Pass-through:** `System` agent, `internal`/`system`/`workflow` tool, `internal`
  MCP server keep their **original** IDs (not copied — assert the array contains the
  same id and no new row was created).
- **Managed MCP that stays visible:** a company-scoped `managed` MCP server
  referenced by the source is **kept by ID** (still `visible_for_project` in the
  same-company target, D4), and **no** managed copy is created. Separately, a managed
  server **not** visible in the target has its reference dropped.
- **Binary tool file (D6/Tool copy):** a source custom tool with a binary
  `ToolFile` (Shrine `file` attachment, `content` blank) is copied so the
  project-local tool's `tool_files` includes a row where `binary?` is true and the
  `file`/`file_data` bytes match the source — not just an empty `content`. A
  text-only `ToolFile` copies its `content`.
- **`requires_integration` (D9):** a copied custom tool carrying
  `requires_integration: "slack"` is created in the project with the same value, and
  is correctly **excluded** from `Tool.visible_for_project(project)` until a Slack
  integration is active for that project (then included).
- **Secrets — POSITIVE and NEGATIVE:** MCP `env`/`headers` are copied **verbatim**
  — a server with `headers: {"Authorization" => "Bearer config_item:API_KEY"}`
  copies that exact string (reference preserved), AND a server with a non-`config_item:`
  literal like `env: {"BASE_URL" => "https://api.example.com", "MODEL" => "gpt-4o"}`
  copies those literals **unchanged** (they must NOT be scrubbed — D3). Lock the
  secrets boundary with the negative assertion that **`ConfigItem.count` does not
  change** (zero `ConfigItem` rows created in the target project) for any of these
  copies.
- Existing name-uniqueness tests (`:42-62`) and the first verbatim test (`:22-40`,
  after the setup is reworked to use real resources, its assertions should now check
  *remapped* IDs) pass.

**Test dependency:** there is **no `test/factories/agents.rb`** (confirmed —
only `agent_credentials.rb` exists). Add an `:agent` factory (mirror
`test/factories/skills.rb` with `:with_company_scope`/`:with_project_scope`
traits and valid `name`/`title`/`persona`) before writing the agent tests.

### Request/integration tests — `test/integration/web/company/workflow_catalog_controller_test.rb` (extend)

Mirror the existing `"duplicate creates workflow copy in target project"`
(`:21-35`). Add a test that seeds a published Company workflow whose step
references a Company agent/skill/mcp, posts `duplicate`, and asserts:
`@project.agents.count`/`skills`/`mcp_servers` increased, the copied step
references the project-local IDs, **and `ConfigItem.count` is unchanged** (the
secrets boundary holds end-to-end through the controller path). Add an idempotency
test (POST twice → no duplicate resources, `ConfigItem.count` still unchanged).

### Model tests

No new model behavior; the `visible_for_project` scopes the design relies on
(`agent.rb:36-39`, `skill.rb:28`, `mcp_server.rb:56-60` — note the managed/custom
non-kind-filtered branches, `tool.rb:61-67` — note the `requires_integration` gate)
are already exercised. No secret-scrub logic exists to test (D3 copies verbatim);
the secrets boundary is asserted via the "no `ConfigItem` rows created" checks in
the service and integration tests above.

### Frontend tests — `app/frontend/pages/Company/WorkflowCatalog/IndexPage.test.tsx`

Existing tests (`:20-93`) still pass (no behavior change). If the modal copy is
updated (§4 Frontend, optional), add an assertion that the
agents/skills/MCP-copied helper text renders. No new picker behavior to test in
`BuilderPage.test.tsx` since IDs are server-supplied.

## 8. Risks & Rollout

- **Risk: existing duplicator tests give false confidence.** The current first
  test asserts verbatim IDs (`[7]`/`[8]`/`[9]`), but those IDs are **phantom** (no
  matching rows), so the defensive `map_*` leaves them unchanged and the assertions
  keep passing even though copying is never actually exercised. Mitigation: rework
  the setup to seed **real** company resources (§7) so the remap path is genuinely
  tested, and gate identity behavior when `target_scope` is a `Company` so
  non-project duplications stay byte-identical to today. Net: few assertions truly
  "break"; the bigger gap is *missing* coverage (especially the `agent_id` FK path),
  which §7 fills.
- **Risk: name collisions in a busy project.** Mitigated by `find_by(name:)`
  reuse (D2); the per-scope unique indexes are never hit. Edge: a project
  already has a *different* resource with the same name — reuse points the
  workflow at that existing resource rather than creating a near-duplicate.
  Acceptable (names are user-meaningful) and called out as behavior; revisit if
  product wants suffixing like `available_name` (`workflow_duplicator.rb:40-48`).
- **Risk: secret leakage.** Bounded by the single boundary "never copy `ConfigItem`
  rows" (D3). `env`/`headers` are copied verbatim (they are user config, not a
  secrets store); `config_item:NAME` references carry no secret material. Covered by
  the "no `ConfigItem` rows created" assertions (§7). Residual risk: a team that
  pasted a raw secret directly into `env`/`headers` (instead of a `config_item:` ref)
  has that literal copied — unavoidable without a discriminator that does not exist,
  and out of scope (D3 data-loss note).
- **Risk: copied binary tool files lost.** A copy that only replicated the `content`
  column would silently drop every binary `ToolFile` (Shrine `file`/`file_data`),
  breaking the tool at runtime (`custom_tool_strategy.rb:60-64`). Mitigated by
  replicating the Shrine `file` attachment for `binary?` tool files (§4 Tool / D6),
  with a dedicated binary-tool-file test (§7).
- **Risk: copied tool invisible due to `requires_integration`.** A copied custom
  tool that requires an integration is hidden from the target project's pickers until
  that integration is connected (`tool.rb:65-66`). This is intentional (D9) but must
  be communicated; folded into Q3.
- **Risk: larger copy transactions.** Copying N resources + `tool_files` in one
  transaction is bounded by the workflow's distinct dependency count (small).
  Acceptable; keep it in the existing single transaction
  (`workflow_duplicator.rb:11`).
- **Performance:** dependency collection should `pluck`/load distinct IDs once
  and batch-load source resources to avoid N+1 across steps.
- **Rollout:** ship behind no flag (pure improvement to the copy path). Existing
  copied workflows are untouched unless the optional backfill (Q2) is approved.
  Verify in Docker per repo convention
  (`docker compose exec -T web bin/rails test test/services/workflow_duplicator_test.rb`
  and the catalog integration test) — not run as part of this design task.
