# Epic 16: Session Outputs, Logs & Config Normalization

> Replace metadata-based artifact storage with proper file persistence (Shrine), introduce user-facing output review flow, and normalize session configuration from JSONB to proper ActiveRecord relations with referential integrity.

**Phase:** 9 (Depends on: Epic 10 Artifacts, Epic 9 Sessions, Epic 15 VS Code Server)

**User Outcome:** Session outputs are saved as real files (Assets), users can review and keep/dismiss them after session ends. Session logs are stored as downloadable files instead of truncated text in metadata. Session configuration has proper database relations — deleting a tool/skill/MCP server cleanly removes it from sessions rather than leaving orphaned IDs in JSON.

---

## Part A: Session Log Collection

### Story 16.1: SessionLog Model & Uploader

**As a** platform engineer,
**I want** session logs stored as real files with Shrine,
**so that** logs aren't truncated in metadata JSON and can be downloaded/analyzed later.

**Acceptance Criteria:**

1. **Migration** — New table `session_logs`: `id`, `terminal_session_id` (bigint, not null, FK → terminal_sessions, index), `name` (string, not null — e.g. "http.log"), `file_data` (text, Shrine), `file_size` (bigint), `content_type` (string), `created_at`, `updated_at`.
2. **Model** — `SessionLog` with `belongs_to :terminal_session`, `include SessionLogUploader::Attachment(:file)`. Validates: name presence, terminal_session presence.
3. **Uploader** — `SessionLogUploader < Shrine`. Plugins: activerecord, determine_mime_type, pretty_location, validation_helpers. Max size 1 GB. Location: `sessions/{session_id}/logs/{name}`.
4. **Relation** — `TerminalSession has_many :session_logs, dependent: :destroy`.
5. **Serializer** — `SessionLogSerializer` with id, name, file_size, content_type, download_url, created_at.

**Dev Notes:**
- Replaces `persist_artifacts_to_session` which stored truncated text in `metadata["artifacts"]`
- Shrine stores files in S3 (production) or filesystem (development), same as AssetFileUploader

---

### Story 16.2: Collect Logs in before_cleanup

**As a** platform engineer,
**I want** `before_cleanup` to create SessionLog records from adapter log paths,
**so that** logs are persisted as downloadable files before the container is destroyed.

**Acceptance Criteria:**

1. **Rename** — Current artifact collection logic becomes `collect_logs` private method in `AgentSessionStrategy`.
2. **Implementation** — For each path from `adapter.session_log_paths`:
   - Read content via `read_file_from_container(container, path)`
   - Skip if blank
   - Wrap in `StringIO` with correct filename
   - Create `SessionLog` with file attachment, associate to session
3. **Remove** — Delete `persist_artifacts_to_session` method and `metadata["artifacts"]` writes.
4. **Remove** — Delete `output_artifact_paths` support from `before_cleanup` (replaced by Story 16.4).
5. **Context result** — Set `context[:result][:logs_count]` with number of collected logs.
6. **Error handling** — Individual log collection failures don't block other logs or the cleanup process.

**Dev Notes:**
- `collect_usage` remains unchanged, just extracted as a separate private method for clarity
- `before_cleanup` becomes: `collect_logs` → `collect_outputs` (Story 16.4) → `collect_usage`

---

## Part B: Session Output Collection & Review

### Story 16.3: Rename Output Directory

**As a** user,
**I want** the session output directory to be called `/workspace/outputs/`,
**so that** naming is consistent and clear.

**Acceptance Criteria:**

1. **Entrypoint** — In `entrypoint.sh`, change `mkdir -p "$WORKSPACE/repo" "$WORKSPACE/output"` → `"$WORKSPACE/outputs"`.
2. **Context file** — In `SessionContextService#build_workspace_layout`, update all references from `/workspace/output/` to `/workspace/outputs/`.
3. **Seeds** — Update any seed data referencing the old path.
4. **Backward compat** — Not needed; each session gets a fresh container.

---

### Story 16.4: Collect Outputs as Pending Assets

**As a** platform engineer,
**I want** files from `/workspace/outputs/` to be collected as Asset records with `pending_review` status,
**so that** users can decide which outputs to keep after a session.

**Acceptance Criteria:**

1. **Migration** — Alter `assets` table:
   - Add `terminal_session_id` (bigint, nullable, FK → terminal_sessions, index)
   - Add `status` (string, not null, default `"active"`, index)
   - Add `reviewed_at` (datetime, nullable)
2. **Model changes** — In `Asset`:
   - Add `belongs_to :terminal_session, optional: true`
   - Add validation: `status` inclusion in `%w[active pending_review dismissed]`
   - Add scopes: `pending_review` → `where(status: "pending_review")`, `dismissed` → `where(status: "dismissed")`
   - Existing `active` scope: update to `where(deleted_at: nil, status: "active")` (or just add status condition)
3. **AssetVersion source** — Add `:session` to `enumerize :source` in `AssetVersion`.
4. **TerminalSession relation** — `has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id`.
5. **Collect logic** — New `collect_outputs` private method in `AgentSessionStrategy`:
   - List files in `/workspace/outputs/` via `list_files_in_container`
   - For each file: read content, determine scope (session.project → Project scope; else → session.user's company → Company scope)
   - Create `Asset(name: filename, status: "pending_review", terminal_session: session, scope: scope, created_by: session.user)`
   - Create `AssetVersion(source: :session, uploaded_by: session.user)` with Shrine file attachment
   - Skip files that fail, log warning, continue
6. **TerminalSession flag** — Add `artifacts_reviewed` (boolean, default `false`) column to `terminal_sessions`.
7. **Size limit** — AssetFileUploader already has 1 GB limit; no changes needed.

**Dev Notes:**
- Scope resolution: `session.project.present? ? ["Project", session.project_id] : ["Company", session.user.company_id]`
- Folder on Asset: `"session-#{session.id}"` to group outputs from same session
- For large binary files, use `Tempfile` instead of `StringIO` to avoid memory pressure
- Container may already be stopped when `before_cleanup` runs; `read_file_from_container` works on stopped containers via `archive_out` (tar)

---

### Story 16.5: Artifact Review API

**As a** user,
**I want** an API to view pending session outputs and make keep/dismiss decisions,
**so that** I control which outputs become permanent project assets.

**Acceptance Criteria:**

1. **Controller** — `Api::V1::Company::TerminalSessions::ArtifactsController`, nested under terminal_sessions.
2. **`GET index`** — Returns pending-review assets for the session. Includes: id, name, folder, file_size, content_type, download_url, created_at. Sorted by name.
3. **`POST review`** — Accepts `{ decisions: { "<asset_id>": "save" | "dismiss" }, target_scope_type: "Project" | "Company", target_scope_id: <id> }`.
   - `"save"` → `asset.update!(status: "active", reviewed_at: Time.current, scope_type: target_scope_type, scope_id: target_scope_id)`
   - `"dismiss"` → `asset.update!(status: "dismissed", reviewed_at: Time.current)`
   - After processing all decisions: `session.update!(artifacts_reviewed: true)`
   - Validate: user has access to target scope
4. **Routes** — Nested: `resources :terminal_sessions do; resource :artifacts, only: [:index], controller: 'terminal_sessions/artifacts' do; post :review; end; end`
5. **Authorization** — User must own the session or be admin of the company.

---

### Story 16.6: Artifact Review Page (Frontend)

**As a** user,
**I want** a dedicated page to review session outputs,
**so that** I can preview files and decide which to keep.

**Acceptance Criteria:**

1. **Route** — `/company/sessions/:sessionId/artifacts` → `SessionArtifactsPage`.
2. **Data** — Fetches pending artifacts via RTK Query (`getSessionArtifacts`).
3. **File list** — Table/cards with: filename, size (formatted), content type. Text files show preview (first 500 lines).
4. **Selection** — Checkboxes per file. Default: unchecked (dismiss by default).
5. **Scope selector** — If session has a project, pre-select it. Otherwise show company. Dropdown to switch.
6. **Actions**:
   - "Save selected" → POST review with save for checked, dismiss for unchecked. Disabled if nothing selected.
   - "Dismiss all" → POST review with all dismissed.
   - Both set `artifacts_reviewed = true` on session.
7. **Post-review** — Navigate back to session view page. Show success toast.
8. **Empty state** — "No outputs collected from this session."
9. **Already reviewed** — If `artifacts_reviewed` is true, show read-only summary of decisions made.

---

### Story 16.7: Session View & List Integration

**As a** user,
**I want** to see when a session has pending outputs to review,
**so that** I don't miss important results.

**Acceptance Criteria:**

1. **Serializer** — Add to `TerminalSessionSerializer`:
   - `artifacts_reviewed` (boolean)
   - `pending_artifacts_count` (integer — `object.output_assets.pending_review.count`)
   - `session_logs_count` (integer — `object.session_logs.count`)
2. **Frontend types** — Add to `ITerminalSession`: `artifactsReviewed`, `pendingArtifactsCount`, `sessionLogsCount`.
3. **Session view page** — In `CompanySessionViewPage`, when session is collected and `!artifactsReviewed && pendingArtifactsCount > 0`:
   - Show prominent "Review outputs (N files)" button in the collected state block, linking to `/company/sessions/:id/artifacts`
4. **Session list** — In `SessionHistoryWidget`, when session is collected and `!artifactsReviewed && pendingArtifactsCount > 0`:
   - Show a small badge/icon next to the status chip indicating pending review
5. **SessionSummaryCard** — Add outputs info to the shared summary card (from entities/terminal-session).

---

### Story 16.8: Dismissed Assets Cleanup

**As a** platform engineer,
**I want** dismissed assets to be automatically cleaned up after a grace period,
**so that** storage isn't wasted on unwanted outputs.

**Acceptance Criteria:**

1. **Temporal activity** — `CleanupDismissedAssetsActivity`: finds `Asset.where(status: "dismissed").where("reviewed_at < ?", 7.days.ago)`.
2. **Cleanup** — For each: destroy all versions (Shrine deletes files from storage), then destroy the asset record.
3. **Scheduling** — Run daily via Temporal scheduled workflow (same pattern as `StaleSessionCleanupWorkflow`).
4. **Logging** — Log count of cleaned assets and freed storage.
5. **Safety** — Only clean assets where `reviewed_at` is set (user explicitly dismissed). Never touch `pending_review` assets — those await user decision.

---

## Part C: Session Config Normalization

### Story 16.9: Session Config Join Tables

**As a** platform engineer,
**I want** session configuration stored in proper join tables with foreign keys,
**so that** deleting a tool/skill/MCP server automatically cleans up session references.

**Acceptance Criteria:**

1. **Migration** — Create join tables (no primary key needed, just composite index):
   - `session_tools`: `terminal_session_id` (FK, not null), `tool_id` (FK, not null). Unique index on both.
   - `session_skills`: `terminal_session_id` (FK, not null), `skill_id` (FK, not null). Unique index on both.
   - `session_mcp_servers`: `terminal_session_id` (FK, not null), `mcp_server_id` (FK, not null). Unique index on both.
   - `session_input_assets`: `terminal_session_id` (FK, not null), `asset_id` (FK, not null). Unique index on both.
   - `session_repositories`: `terminal_session_id` (FK, not null), `repository_id` (FK, not null). Unique index on both.
2. **Migration** — Add `configured_agent_id` (bigint, nullable, FK → agents) to `terminal_sessions`. Add `mode` (string, default "interactive") and `initial_prompt` (text, nullable) as real columns.
3. **Model relations** — On `TerminalSession`:
   - `has_and_belongs_to_many :tools, join_table: :session_tools`
   - `has_and_belongs_to_many :skills, join_table: :session_skills`
   - `has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers`
   - `has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets`
   - `has_and_belongs_to_many :repositories, join_table: :session_repositories`
   - `belongs_to :configured_agent, class_name: "Agent", optional: true`
4. **On entity deletion** — Add `dependent: :nullify` or configure FK with `ON DELETE CASCADE` on the join tables so deleting a Tool/Skill/etc. removes the join record (not the session).
5. **Validation** — Validate that referenced entities exist and are accessible to the session's user/project at creation time.
6. **Keep config_files and env_vars** — These remain as JSONB (dynamic key-value data, not entity references). Rename or keep in `session_config` jsonb for these two fields only.

**Dev Notes:**
- FK constraint `ON DELETE CASCADE` on join tables means deleting a Tool automatically removes all `session_tools` rows referencing it — clean, no orphans
- `configured_agent_id` uses `ON DELETE SET NULL` — session keeps existing but agent reference cleared
- `config_files` and `env_vars` are truly dynamic (user-defined keys/values), not entity references, so JSONB is appropriate for them
- `mode` and `initial_prompt` move to real columns since they're always present and validated

---

### Story 16.10: Migrate Existing Session Config Data

**As a** platform engineer,
**I want** existing `session_config` JSONB data migrated to the new relations,
**so that** the transition is seamless and no data is lost.

**Acceptance Criteria:**

1. **Data migration** — Ruby migration script that for each `TerminalSession` with non-empty `session_config`:
   - Reads `tool_ids` → inserts into `session_tools` (skip IDs where Tool no longer exists)
   - Reads `skill_ids` → inserts into `session_skills`
   - Reads `mcp_server_ids` → inserts into `session_mcp_servers`
   - Reads `asset_ids` → inserts into `session_input_assets`
   - Reads `repository_ids` → inserts into `session_repositories`
   - Reads `agent_id` → sets `configured_agent_id`
   - Reads `mode` → sets `mode` column
   - Reads `initial_prompt` → sets `initial_prompt` column
   - Keeps `config_files` and `env_vars` in `session_config`
2. **Cleanup** — After migration, remove migrated keys from `session_config` JSONB (keep only `config_files`, `env_vars`).
3. **Idempotent** — Migration can be run multiple times safely (skip if join records already exist).
4. **Batch** — Process in batches of 500 to avoid memory issues.

---

### Story 16.11: Update Services & API for Normalized Config

**As a** platform engineer,
**I want** all services and API endpoints to use the new relations instead of JSONB,
**so that** the codebase is consistent and the old accessors are removed.

**Acceptance Criteria:**

1. **TerminalSession model** — Remove JSONB accessor methods (`tool_ids`, `skill_ids`, `mcp_server_ids`, `asset_ids`, `repository_ids`, `configured_agent_id`, `mode`, `initial_prompt`). Replace with relation-based equivalents where needed (e.g. `tool_ids` → `tools.pluck(:id)`).
2. **SessionContextService** — Update all references:
   - `session.tool_ids` → `session.tool_ids` (HABTM provides this)
   - `session.mcp_server_ids` → `session.mcp_server_ids`
   - `session.skill_ids` → `session.skill_ids`
   - `session.asset_ids` → `session.input_asset_ids`
   - `session.repository_ids` → `session.repository_ids`
   - `session.configured_agent_id` → `session.configured_agent_id` (now a real column)
   - `session.mode` → `session.mode` (now a real column)
   - `session.initial_prompt` → `session.initial_prompt` (now a real column)
3. **Terminal sessions controller** — Update create/update params to accept nested relation IDs (`tool_ids: [...]` etc.) and assign through relations.
4. **Serializer** — Update `TerminalSessionSerializer` and `ISessionConfig` frontend type. Session config now only contains `configFiles` and `envVars`. Tools, skills, etc. are top-level arrays or counts.
5. **Frontend** — Update `CompanySessionNewPage` form to submit relation IDs. Update `ITerminalSession` and `ISessionConfig` types.
6. **Validation** — Remove `ALLOWED_SESSION_CONFIG_KEYS` and `validate_session_config`. Replace with proper relation validations.
7. **Remove** — Delete `session_config` accessor methods that are now redundant. Keep `session_config` column only for `config_files` and `env_vars`.

**Dev Notes:**
- HABTM collections automatically provide `tool_ids`, `tool_ids=` methods in Rails
- Existing API contract `{ session_config: { tool_ids: [...] } }` changes to `{ tool_ids: [...], mode: "...", initial_prompt: "..." }` — breaking change, coordinate with frontend
- `available_tools` method logic stays similar but reads from `self.tools` relation instead of `Tool.where(id: tool_ids)`

---

## Dependencies

```
16.1 (SessionLog model)
  └── 16.2 (collect_logs in before_cleanup)

16.3 (rename outputs dir)
  └── 16.4 (collect outputs as Assets)
        ├── 16.5 (review API)
        │     └── 16.6 (review page)
        │           └── 16.7 (view/list integration)
        └── 16.8 (dismissed cleanup job)

16.9 (join tables)
  └── 16.10 (data migration)
        └── 16.11 (update services & API)
```

Stories 16.1-16.2 and 16.9-16.10 can be developed in parallel.
