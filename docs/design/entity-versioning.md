# RFC: Version history, revert and archive for workflows, agents, skills, tools and MCP servers

**Status:** Implemented (see §13 for how the build differs from the first draft)
**Date:** 2026-09-25
**Baseline:** `develop` @ `6ffc0e61`
**Scope:** Every explicit save of a workflow (with its steps and sub-steps), agent, skill, custom tool or MCP server becomes an immutable, numbered version. Each entity gets a Versions tab with diffs and revert. Delete becomes archive, and every list screen shows the archive.

---

## 1. Problem

People change live agents and workflows. When a change breaks something, nobody can tell who made it, what exactly changed, or what the previous working state was. There is also no way to put it back. Nothing records which configuration a run or session actually executed.

The request came from the CTO after the team worked on Insignia and on internal workflows, and the FDE confirmed the need. The requirements:

- a full version history: who changed what, and the diff;
- revert to any earlier version;
- the version each run and session actually executed;
- nothing that has run can be deleted, it can only be archived.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | **The live row is the current version.** There is no draft/publish split. Saving updates the model and appends a full snapshot to its history. |
| D2 | **Only an explicit Save creates a version.** Builder autosave goes away. The UI shows an "unsaved changes" notice as soon as local state differs from the backend. |
| D3 | **Revert applies the snapshot to the model and records a new version** (`restored_from` vN). History is append-only and never rewritten. |
| D4 | **Runtime is unchanged.** It keeps reading live rows, so it always runs the latest version. Runs and sessions only record the versions they launched with. |
| D5 | **Versioned entities:** workflow (+ steps + sub-steps), agent, skill (+ files), custom tool (+ tool files), MCP server. |
| D6 | **Delete becomes archive for all five.** There is no permanent delete for now, it will be decided later. |
| D7 | **A snapshot is a full dump,** not a field-level delta. Diffs are computed between two snapshots. |
| D8 | **One polymorphic version table, one diff component, one Versions tab** for all five types. |
| D9 | **Version history is kept indefinitely.** |

### Non-goals

- **Draft/publish, or pinning a run to one version.** Saving mid-run affects the steps that have not launched yet, as it does today. D4 makes that visible instead of preventing it. See §10.
- **Pausing or versioning the task board.** Board and column edits stay as they are.
- **Permanent delete** (D6).
- **Versioning secrets, OAuth connections or system-maintained state** (§8.1).
- **Code-defined tools** (`source: "code"`). Git versions them.
- **Triggers, config items, repositories and project settings.** They are not versioned in this iteration.

## 3. Current state

### 3.1 Nothing records history

- The `audited` gem was removed in #309. `app/models/audit.rb` keeps the old `audits` table for administrative actions only (sign-outs, impersonation, permanent user deletion), written by hand. Its header says "nothing is audited by callback", and that is a deliberate doctrine. This design follows it: versions are created explicitly by a service, not by model callbacks.
- `Current` only holds `user_session` (`app/models/current.rb`). There is no request-wide actor:
  - controllers use `current_user`;
  - personal MCP tools receive `user:` (`personal_tools/base.rb:21`);
  - the Aixle Builder runs the same tools as `session.user` (`tools/builder_toolset.rb:52`), so an agent's edit looks like the human's.
- The only change trail today is `terminal_session.metadata["builder_activities"]`: the last 100 builder writes, with no diff.

### 3.2 How entities are written

- **Web (Inertia) controllers** under `app/controllers/web/company/projects/` save agents, tools, MCP servers and skills from a modal with a Save button.
- **The workflow builder** (`app/frontend/pages/Projects/Workflows/BuilderPage.tsx`) autosaves:
  - one PATCH per field after a 500 ms debounce;
  - immediate saves for pickers, add/remove sub-step, add/delete/reorder step;
  - a flush on unmount and when the tab is hidden.
- **JSON API** under `app/controllers/api/v1/projects/workflows/` (steps, sub-steps via `sub_steps_attributes`, reorder).
- **About 15 personal MCP tools** write these five types directly (`update_workflow`, `update_workflow_step`, `create_sub_step`, `update_agent`, `update_skill`, `install_skill`, `update_mcp_server`, `install_connector`, `update_custom_tool`, `duplicate_workflow`, …).
- **System writers:**
  - `WorkflowDuplicator` (+ `DependencyCopier`), `SkillsRegistryService.install`, `MCP::ConnectorInstaller`, `MCP::ConnectorUpdater`;
  - `MCP::ToolDriftDetector` and `Tools::Reconciler` also write, but produce system state, not versions (§8.1).
- **Writes that bypass callbacks:**
  - step and board-column reorder go through `Positions.reorder!` (`update_column`);
  - sub-step reorder loops `update_column`;
  - step and sub-step soft delete use `update_column`.

### 3.3 How entities are deleted

| Entity | Today |
|---|---|
| Workflow | `Workflow#soft_delete!` from every path. Refused while a run is live or a column is bound. Disables enabled triggers. Runs are kept. |
| Step / SubStep | Soft delete (`update_column`) **only if it has runs**, otherwise a hard delete (`step.rb:42`, `sub_step.rb:20`). |
| Tool | `soft_delete!` sets `deleted_at` but leaves `enabled` on. |
| Agent | Hard delete. `steps.agent_id` and `terminal_sessions.configured_agent_id` are nullified. |
| Skill | Hard delete. `session_skills` rows cascade. |
| MCP server | Hard delete. OAuth credentials, the manual OAuth client and `session_mcp_servers` cascade. |

No list screen shows deleted items.

### 3.4 How runtime reads config

Runs store ids only. Runtime reads live rows in about 20 places:

- the step list at run start (`PrepareStepListActivity`);
- per step: `CheckSkipActivity`, `PrepareStepActivity`, sub-step runs, `SessionService.build_for_workflow_step`, `SessionConfigResolver`;
- at container boot: the prompt from live `step.instructions` in `WorkflowStepStrategy#agent_prompt`, model, skills, MCP servers, context builders;
- on every tool call: `TerminalSession#available_tools`.

This design does not change those reads (D4). It records what they resolved to (§7).

Registry skills now carry their whole directory in `skills.files` (#309), and boot writes those files instead of fetching upstream (`session_context_service.rb:246`). That makes a skill snapshot complete.

### 3.5 Name collision

`Workflow#publish!` and `published_at` mean "shared to the company workflow catalog" (`workflow.rb:83`). This design introduces no "publish" wording.

## 4. Data model

### 4.1 `entity_versions`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `versionable_type`, `versionable_id` | string, bigint | `Workflow`, `Agent`, `Skill`, `Tool`, `MCPServer` |
| `number` | integer | 1..n per versionable. Unique index on `(versionable_type, versionable_id, number)` |
| `event` | string | `created`, `saved`, `reverted`, `archived`, `restored` |
| `snapshot` | jsonb | the full dump (§4.2). Present on every event, so any version can be diffed and reverted to |
| `snapshot_format` | integer | serializer format version, so old snapshots stay readable when a type's shape changes |
| `restored_from_id` | bigint, nullable | the version a `reverted` event applied |
| `author_id` | bigint → users, nullable | `on_delete: :nullify`, so history outlives a deleted user |
| `source` | string | `ui`, `api`, `mcp`, `builder`, `system` |
| `terminal_session_id` | bigint, nullable | set for `builder` and `mcp` writes made from a session. `on_delete: :nullify` |
| `metadata` | jsonb | event details, e.g. the trigger ids a workflow archive disabled (§6.3) |
| `project_id`, `company_id` | bigint | same FK and CHECK pattern as `TenantColumns` (#309) |
| `created_at` | datetime | no `updated_at`: rows are immutable |

Indexes:

- `(versionable_type, versionable_id, number DESC)` for the timeline and keyset pagination;
- `(terminal_session_id)` for "what did this builder session change";
- `(project_id, created_at)` for a future project-wide feed.

Each versioned model gets `lock_version`-style protection through `current_version_number`, a denormalized integer column (§5.3).

### 4.2 Snapshot contents

| Type | Included | Excluded |
|---|---|---|
| **Workflow** | `name`, `description`, `config` (all `base_*_ids`, `inherit_all_project_resources`). **Live steps** (soft-deleted ones are not in the snapshot; their rows stay so a revert can bring them back), each with id and every column `WorkflowDuplicator#duplicate_step` copies: `name`, `instructions`, `position`, `agent_id`, `preferred_model`, `required_agent_runtime`, `skip_policy`, `on_failure`, `max_retries`, `input_asset_specs`, `output_asset_specs`, `tool_ids`, `skill_ids`, `mcp_server_ids`, `asset_ids`, `repository_ids`, `config_item_ids`, `depends_on_step_ids`, `bmad_enabled`, `allow_non_interactive`. **Live sub-steps** per step: id, `name`, `instructions`, `position`, `required`. | `published_at`/`published_by_id` (catalog sharing), timestamps, triggers and column bindings |
| **Agent** | `name`, `title`, `icon`, `persona`, `communication_style`, `principles`, `source` | timestamps |
| **Skill** | `name`, `title`, `description`, `content`, `files` (`{path => contents}`), `origin`, `source`, `source_url`, `package`, `content_hash` | `install_count`, timestamps |
| **Tool** (`source: "db"` only) | `name`, `display_name`, `description`, `command`, `docker_image`, `execution_mode`, `input_schema`, `required_config_items`, `requires_integration`, `tags`, `enabled`, `user_attachable`. **Tool files**: `path`, `content` (text), `file_data` (Shrine reference, §8.2). | `definition_digest` (derived, §8.3), `docker_image_digest` (the pin the platform resolves), timestamps |
| **MCP server** | `name`, `description`, `transport`, `url`, `command`, `args`, `auth_type`, `credential_scope`, `enabled`, `kind`, `connector_name`, `connector_version`, `connector_manifest`. **Secret fingerprints**: `env` and `headers` as `{key => "hmac:…"}` (§8.1). | secret values, `tool_snapshot`, `tool_drift`, `tool_snapshot_at`, OAuth credentials and client, timestamps |

Snapshots are produced by one serializer per type, `Versions::Snapshot::<Type>`, and read back by the matching `Versions::Restore::<Type>`. The column lists live in one place per type. A test asserts that every column of the table is either snapshotted or explicitly excluded, so a new column cannot silently fall out of history.

## 5. Write path

### 5.1 One entry point

```ruby
Versions.save!(record, actor:, source:, session: nil, base_version: nil) do
  # mutate record (and its children) here
end
```

Inside one transaction it:

1. locks the versionable row (`SELECT … FOR UPDATE`);
2. checks `base_version` against `current_version_number` and raises `Versions::StaleVersion` on mismatch (§5.3);
3. yields for the mutation;
4. returns without a version if the resulting snapshot equals the latest one, so a no-op save stays a no-op;
5. otherwise inserts the `entity_versions` row with `number = current + 1` and bumps `current_version_number`.

The snapshot is read from the database after the mutation, inside the transaction. That is why writes through `update_column` (`Positions.reorder!`, soft deletes) are captured without any callback: the service snapshots state, not events.

`Versions.archive!`, `Versions.restore!` and `Versions.revert!` are thin wrappers that set `event` and `metadata`.

### 5.2 Wiring every writer

Every path in §3.2 that changes a versioned type goes through `Versions.save!`:

| Writer | Change |
|---|---|
| Web controllers (agents, tools, MCP servers, skills) | wrap the existing `update`/`create`, `source: "ui"` |
| API workflow and step controllers | replaced by the aggregate endpoint (§5.4); old per-field endpoints removed once the builder moves |
| Personal MCP tools | wrap in `Versions.save!`, `source: "mcp"`. When called through `BuilderToolset`: `source: "builder"`, `session: session` |
| `WorkflowDuplicator` | the copy gets version 1 (`created`), with `metadata.duplicated_from` |
| `SkillsRegistryService.install`, `MCP::ConnectorInstaller`, `MCP::ConnectorUpdater` | `created`/`saved`, `source: "system"` when no user acted, otherwise the acting user |
| `ToolDriftDetector`, `Tools::Reconciler`, `Workflow#publish!` | **not wired**: system state, code tools, catalog sharing |

Two guards keep this complete:

- an architecture test that fails when a new personal tool or controller writes one of the five models outside `Versions.save!`;
- the snapshot completeness test from §4.2.

### 5.3 Concurrent edits

Every edit form and the builder load `current_version_number` and send it back as `base_version`. If someone saved in between, the server answers **409** with the newer version number. The UI then says the entity was changed and offers to reload and see the diff.

MCP tools accept an optional `base_version`. Without it they apply last-writer-wins, since agents re-read before they write (the MCP server instructions already require that).

### 5.4 The builder moves to explicit save

- `BuilderPage` holds the whole aggregate (workflow, steps, sub-steps, order, deletions) in local state. There are no network writes while editing.
- **Save** sends the aggregate to a new `PUT /api/v1/projects/:project_id/workflows/:id` with `base_version`. The server diffs it against the database and applies it in one `Versions.save!`:
  - upsert steps and sub-steps by id, creating the ones with client-side temporary ids;
  - soft-delete the missing ones;
  - renumber positions;
  - validate the dependency DAG.
  This produces one version per Save.
- **Unsaved changes:** the page keeps the server snapshot it loaded. When local state differs from it, a persistent notice says "You have unsaved changes" next to the Save button. It appears on the first change and clears after a successful save or a discard.
  - Leaving the page with unsaved changes asks for confirmation: a `beforeunload` handler plus an Inertia `router.on("before")` guard.
  - The autosave-specific machinery (`use-debounce`, `saveStepFieldImmediate`, `flushOnUnmount`, `useFlushWhenHidden`) is removed.
- Agent, tool, MCP server and skill modals already save explicitly. They gain `base_version` and the same unsaved-changes guard when the modal is closed with edits.

## 6. Revert and archive

### 6.1 Revert

`Versions.revert!(record, to:, actor:, base_version:)`:

1. Loads the target snapshot and runs `Versions::Restore::<Type>`, which assigns attributes and saves **through the model**, with `save!` and validations and callbacks on, never `update_columns`.
2. Records a `reverted` version with `restored_from_id`, as the new latest version.

Per type:

- **Workflow:** for each step in the snapshot, find it by id (including soft-deleted), clear or set `deleted_at` to match, and assign its fields. Steps present now but absent from the snapshot are soft-deleted. Sub-steps work the same way. Ids are stable (§8.4), so `depends_on_step_ids` needs no remapping. The DAG is validated before commit.
- **Tool:** assigns attributes and rebuilds tool files: text content inline, binary files by writing the stored `file_data` back (§8.2). `definition_digest` is restamped by `before_save` (§8.3).
- **MCP server:** assigns non-secret attributes. Secret values are left as they are (§8.1).
- **Agent, skill:** assign attributes.

The revert dialog always shows the diff **against the current version** (§9.2) and lists the side effects before confirming:

- references to archived entities (§8.5);
- secrets that will be reset because the MCP destination changes (§8.1);
- secret keys the old version had that now need a value;
- a name that is now taken by another entity (§8.7).

### 6.2 Archive

- Archive replaces delete in the UI, the API and the personal MCP tools. `delete_*` tools archive. Tool descriptions and the MCP server instructions say so.
- Columns:
  - **Agent, Skill, MCPServer:** a new `archived_at` column;
  - **Tool:** keeps its `deleted_at` (renamed in code to archive semantics);
  - **Workflow:** keeps its `deleted_at` and `soft_delete!`.
- Archiving is refused while the entity is referenced by an active workflow (agent via `steps.agent_id`; tool, skill or MCP server via step `*_ids` or workflow `base_*_ids`). The error lists the workflows and steps.
- Archived entities are hidden from pickers, from `visible_for_project` and from runtime resolution. That includes `TerminalSession#available_tools` (§8.6).
- Session join rows no longer cascade on archive, since the rows are not deleted. Past sessions keep their links.
- MCP OAuth credentials survive archive and are usable again after restore.

### 6.3 Restore

`Versions.restore!` clears the archive column after checking for name conflicts (§8.7) and records a `restored` version.

For a workflow, the `archived` version's `metadata.disabled_trigger_ids` records which triggers archiving turned off. Restore offers to switch exactly those back on.

### 6.4 UI

Every list screen (Workflows, Agents, Skills, Tools, MCP servers) gets an **Archived** tab or filter. Each row shows who archived it and when, plus a **Restore** button. There is no permanent delete (D6).

## 7. Recording what ran

| Where | New column | Set when |
|---|---|---|
| `step_runs` | `workflow_version_id` → `entity_versions` | the step launches (`PrepareStepActivity`) |
| `terminal_sessions` | `version_ids` jsonb: `{agent: id, skills: [ids], tools: [ids], mcp_servers: [ids], workflow: id}` | the session is built (`SessionService.build_for_workflow_step`, `create_and_start`), from the resources it resolved |

These are written from activities and services only. Per `docs/architecture/temporal-versioning.md`, changing what an activity does is replay-safe and needs no `Workflow.patched`.

The run page shows the version per step. When steps of one run executed different workflow versions, it says so ("version changed during this run: v7 → v8"), linking to the diff.

## 8. Hazards and how they are handled

### 8.1 MCP secrets

**Values are never stored in a snapshot.** For `env` and `headers`:

- the snapshot keeps each key with an HMAC of its value, keyed with an application secret. A plain SHA would let a short token be brute-forced from history;
- the diff shows "`API_KEY` added", "`TOKEN` value changed" or "`X-Org` removed", never a value.

**Revert leaves current secret values alone.** If the target version had keys that are now absent, the dialog lists them as needing a value.

**Changing the destination resets secrets, and revert must not bypass that.** `MCPServer#forget_secrets_for_new_destination` (`mcp_server.rb:332`) drops every secret not re-supplied in the same save when transport, url, command or args change. `disconnect_from_old_destination` also drops OAuth connections. Revert saves through the model without supplying secrets, so the rule fires on its own. The dialog warns beforehand that secrets and OAuth connections will be reset. Supplying current secrets during a revert would turn revert into a way to send credentials to an old or foreign destination, so it is not allowed.

*Rejected:* storing ciphertext in snapshots for full-fidelity revert.

- Secret copies would multiply across versions.
- A token revoked after a leak would survive in history, and a revert would resurrect it.
- Every key rotation or recrypt would have to cover versions too.

**Not versioned:** `tool_snapshot`, `tool_drift`, `tool_snapshot_at`, OAuth credentials, the manual OAuth client. `MCP::ToolDriftDetector` keeps writing them directly and creates no versions.

### 8.2 Tool files in object storage

**Problem.** A snapshot references a binary file by `file_data`. With the `activerecord` plugin, Shrine deletes the previous object when a file is replaced and the object when a `ToolFile` row is destroyed. `allow_destroy` on the tool form destroys rows. Old snapshots would point at nothing.

**Solution: immutable objects plus reference-checked garbage collection.**

- `ToolFileUploader`'s attacher stops deleting previous or destroyed files (override `destroy_previous` / `destroy_attached`).
- Locations are already unique per upload (`tool_files/<tool>/<uid>/<name>`, `tool_file_uploader.rb:20`), so nothing is ever overwritten.
- A daily job deletes objects under `tool_files/` that no live `ToolFile` row and no snapshot references. Under D9 this only removes abandoned uploads (cache promotions from forms that were never saved).
- Revert writes the stored `file_data` back onto the row; the object is still in `store`.
- Text files (`tool_files.content`) are inlined in the snapshot.

*Rejected:* copying each object into a `versions/` prefix on every save. It doubles storage for files up to 50 MB, and disabling deletion gives the same guarantee.

### 8.3 `definition_digest`

`Tool#stamp_definition_digest` runs in `before_save` (`tool.rb:46`). Revert saves through the model, so the digest is recomputed and `definition_digest_intact?` keeps serving the tool. A write through `update_columns` would fail it closed.

**Rule:** restore never uses `update_columns`/`update_all`. A test covers "revert a tool → the tool is still served to an agent".

### 8.4 Hard-deleted steps break revert

**Problem.** `Step#destroy` and `SubStep#destroy` hard-delete when there are no runs. A snapshot could reference a step id that no longer exists, and its dependants' `depends_on_step_ids` would dangle.

**Solution:** steps and sub-steps are always soft-deleted. Ids then stay valid forever, and revert only toggles `deleted_at` and assigns fields. `Positions.reorder!` already accounts for soft-deleted positions. History starts empty at launch, so no snapshot predates this rule.

### 8.5 Snapshots that reference archived entities

A workflow snapshot carries `agent_id`, `tool_ids`, `skill_ids`, `mcp_server_ids`, `repository_ids`, `config_item_ids`. Revert can bring back a reference to something now archived.

- The revert dialog lists them, with "restore them too" or "revert without them".
- Runtime filters archived entities anyway. The builder shows a visible "archived" badge on any step still pointing at one, so it does not silently do nothing.
- Archiving is refused while an entity is referenced by an active workflow (§6.2), so this only arises through revert.

### 8.6 Archived tools are still served (existing bug)

`TerminalSession#available_tools` filters attached tools on `enabled` only (`terminal_session.rb:292`), and `Tool#soft_delete!` does not clear `enabled`. An archived tool that is still attached keeps being served.

**Fix:** filter archived tools there, with a test. This is independent of the rest and should land first.

### 8.7 Name conflicts on revert and restore

Names are unique among non-archived rows. A revert that renames to a now-taken name, or a restore whose name was reused, fails validation. The dialog shows the conflict and asks for a new name. Names are never suffixed silently.

### 8.8 Version volume from agents

A builder session can save dozens of times. Versions record `source: "builder"` and the session. The timeline collapses consecutive versions from one session into one expandable group ("Aixle Builder · 14 changes").

### 8.9 Skill snapshot size

`files` can reach 2 MB per skill, and each save stores a full copy. Skills are saved rarely, so the first version stores them inline. If volume grows, files can be deduplicated by content hash into a side table, with the snapshot keeping references. That is a follow-up, not part of this RFC.

## 9. UI

### 9.1 Versions tab

- Present on the workflow builder and on the agent, skill, tool and MCP server detail screens.
- A timeline, newest first, with infinite scroll: keyset pagination on `number` with `pagy`, reusing the frontend infinite-page pattern the board task list uses.
- Each entry shows:
  - number, event, author (or "Aixle Builder" plus a session link), source and time;
  - for reverts, "restored from vN".

### 9.2 Diff: which side is compared

- **In the timeline, each version is compared with its previous version**, answering "what did this save change".
- **In the revert dialog, the target is compared with the current version**, answering "what will change if I revert".
- The version view has a toggle: "vs previous" / "vs current". It is the same component with a different right-hand side.

### 9.3 `VersionDiff` component

The component takes two snapshots and a per-type field schema. The backend returns snapshots and the frontend computes the diff. The schema declares:

- **scalars** (`name`, `preferred_model`, `enabled`, …), rendered as before → after;
- **long text** (`instructions`, `persona`, `principles`, skill `content`, tool `command`, file contents), rendered as a line diff;
- **keyed collections**, matched by a stable key and rendered as added, removed, changed or moved:
  - steps and sub-steps by id;
  - skill and tool files by path;
  - secret keys by name;
  - `args` by index;
- **id lists** (`tool_ids`, …), rendered as added/removed entity names, resolved through a small lookup endpoint that also returns archived names.

Unchanged fields are collapsed. The only new dependency is `diff` (jsdiff) for line diffs; the structural part is written against the schema.

## 10. Runs during a save

Runtime reads live rows (§3.4), so a save during a run changes the steps that have not launched yet. That includes the prompt, which is read from the live step at container boot. The current architecture does not allow more, and D4 accepts it.

§7 makes it visible per step. Pinning a whole run to one version would mean moving the ~20 read points in §3.4 onto the snapshot. It stays possible later, because every step run will already carry a version id.

## 11. Delivery

| Phase | Content | Estimate |
|---|---|---|
| 0 | Independent fixes: archived tools not served (§8.6); steps and sub-steps always soft-deleted (§8.4) | 2–3 days |
| 1 | Core: `entity_versions`, `Versions.save!/revert!/archive!/restore!`, 409 handling; snapshot and restore for **agent and skill**; wire their writers; `VersionDiff` + Versions tab with infinite scroll; Archived tab for agents and skills | 2.5–3 weeks |
| 2 | **Tool and MCP server:** snapshots, secret fingerprints and the destination-reset warning (§8.1), Shrine retention + GC job (§8.2), digest test (§8.3), archive for MCP servers | 1.5–2 weeks |
| 3 | **Workflow:** aggregate snapshot and restore, aggregate `PUT` endpoint, builder rewrite to explicit save with the unsaved-changes guard, Archived tab + restore with triggers | 2–2.5 weeks |
| 4 | Recording what ran: `step_runs.workflow_version_id`, `terminal_sessions.version_ids`, run-page display and "version changed during this run" | ~0.5 week |

**Total: about 7.5–9.5 weeks for one developer.**

Agents and skills go first because their modals already save explicitly, so the core and the diff component can be proven there before the builder rewrite.

Each phase ships on its own. Entities start with an empty history at deployment; the first save after deployment records version 1. Optionally, a one-time task records a `created` baseline for every existing row, so that the first real change has something to diff against.

## 12. Open questions

1. **Permanent delete:** whether it ever exists (for example, only for entities that never ran), and who may use it.
2. **Retention:** D9 says indefinite. Revisit if skill snapshots grow (§8.9).
3. **Triggers:** whether trigger bindings become part of the workflow snapshot in a later iteration.
4. **Project-wide activity feed:** the `(project_id, created_at)` index allows a "recent changes across the project" page, which is not scoped here.

## 13. As built

The implementation follows this RFC with these differences and specifics:

- **Code map.** `Versions` (`app/services/versions.rb`: `save!`, `revert!`,
  `archive!`, `restore!`, `ensure_baseline!`), one serializer per type under
  `app/services/versions/snapshots/`, `Versions::References` (archive guard),
  `Versions::ReferenceNames` (names for a diff), `Versions::LaunchRecord` (§7),
  and `WorkflowStepSync`, the one writer behind both a workflow revert and the
  builder's Save. Models include `Versioned`; agents, skills and MCP servers
  also `Archivable`.
- **Baseline is lazy.** An entity that predates version history gets a
  `created` version with `metadata.baseline = true` (source `system`) from its
  state just before its first change — or at its first launch, when a run
  records what it used. No backfill task is needed.
- **Snapshots hold live steps only.** Soft-deleted steps and sub-steps are left
  out; a revert soft-deletes live steps the snapshot lacks and brings back the
  ones it names by clearing `deleted_at` (§8.4 made steps and sub-steps always
  soft-deleted).
- **No object sweep.** History is kept indefinitely (D9), so every stored tool
  file stays referenced; `ToolFileUploader` simply never deletes. A retention
  policy would have to bring a sweep with it.
- **`docker_image_digest` is not versioned.** It is the pin the platform
  resolves for `docker_image`, i.e. system state.
- **API.** `GET/POST /api/v1/projects/:project_id/entity_versions` —
  `index` (`versionable_type`, `versionable_id`, `before`; 20 per page,
  `nextBefore`), `show` (the version with `snapshot`, `previousSnapshot`,
  `currentSnapshot` and `references`, snapshot keys verbatim), `revert`
  (`base_version`) and `restore` (`enable_trigger_ids`). The builder saves
  through `PUT /api/v1/projects/:project_id/workflows/:id/aggregate`
  (`base_version`, `aggregate: { name, description, config, steps }`, new steps
  keyed by a client `key`). A stale `base_version` answers 409 with
  `currentVersionNumber` everywhere, including the Inertia forms (a flash alert).
- **Personal MCP tools** take an optional `base_version`, and the read tools
  return `current_version_number`. `delete_*` / `uninstall_skill` archive.
- **Completeness guards.** `Versions::SnapshotCompletenessTest` fails on an
  unclassified column; `Versions::WritePathCoverageTest` fails on a personal
  tool or controller that writes a versioned entity without `Versions`.
- **UI.** A shared `VersionDiff` computes diffs client-side from per-type
  schemas (`shared/lib/versionSchemas.ts`); `VersionHistoryDrawer` (timeline,
  diff vs previous/current, revert with warnings), `ArchivedList` and an
  Active/Archived switch on the Workflows, Agents, Skills, Wrappers and
  Connectors screens. The builder keeps a local draft and saves it with one
  **Save**; forms show *Unsaved changes* and ask before discarding them. The
  run page shows the workflow version per session and flags a run whose
  sessions ran different versions.

