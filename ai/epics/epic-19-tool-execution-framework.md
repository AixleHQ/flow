# Epic 19: Tool Execution Framework

> Unified strategy hierarchy for all tool types, persistent result storage via ToolResult + Shrine, and async-first container execution with presigned URL delivery.

**Phase:** 12 (Depends on: Epic 6 Tools, Epic 8 Container Execution, Epic 17 Container Simplification, Epic 18 Internal Tools)

**User Outcome:** Container-based tools (custom and internal) execute reliably through Temporal without payload limits or timeout issues. Agents receive compact execution IDs, download full results via presigned URLs, and never bloat their context window. New internal container tools can be added in ~15 lines of DSL.

**Architecture:** [Tool Execution Framework](../tool-execution-framework.md)

---

## Problem

The current tool execution has four structural issues:

1. **Split execution paths.** Custom tools go through `ToolExecutionStrategy` → Temporal. Internal container tools (`code_climate`) go through `InternalToolExecutor` → Ruby wrapper → `ContainerService` directly, bypassing Temporal. This creates inconsistent timeout handling, no retry support, and duplicated phase logic.

2. **Temporal payload limits.** Tool stdout/stderr is returned as Temporal activity result. Large outputs (CodeClimate JSON on big repos = 5-10MB) exceed Temporal's 2MB default payload limit. There is no mechanism to persist results outside the workflow.

3. **MCP context window bloat.** MCP `tools/call` returns full stdout to the agent. Agent runtimes (Claude Code, Cursor) place the entire response into context. A 2MB JSON analysis report destroys the context window and wastes tokens. Agents cannot redirect MCP responses to files.

4. **Per-tool strategy boilerplate.** Each new container-based internal tool requires two classes (~200+ lines): a Ruby handler in `InternalTools::` and a full strategy in `ContainerStrategies::`. Most of this code is identical lifecycle management (pull, create, start, wait, cleanup).

---

## Architecture Summary

```
Tool#execute(parameters, session, ...)
  │
  ├── execution_mode == :app
  │     └── InternalToolExecutor → Ruby handler (sync, direct result)
  │         (list_sub_steps, mark_sub_step, write_step_note, read_tool_result)
  │
  └── execution_mode == :container
        │
        ├── Create ToolResult (state: processing)
        ├── Build strategy:
        │     ├── custom? → CustomToolStrategy (image/cmd from Tool model)
        │     └── internal? → InternalToolStrategy (image/cmd from DSL definition)
        ├── Temporal start_workflow (async, non-blocking)
        └── Return tool_result.execution_id to MCP
              │
              │  ... container runs ...
              │
              ├── ToolStrategy#exec persists stdout/stderr/files → ToolResult (Shrine/S3)
              ├── Temporal activity returns tiny payload: { tool_result_id, exit_code }
              │
              └── Agent calls read_tool_result → gets presigned URLs → curl downloads to file
```

Strategy hierarchy:

```
BaseStrategy (existing)
  └── ToolStrategy (NEW — shared exec/timeout/persist logic)
        ├── CustomToolStrategy (NEW — replaces ToolExecutionStrategy)
        └── InternalToolStrategy (NEW — DSL-based definitions)
```

---

## Stories

### Story 19.1: Add `execution_mode` to Tool Model

**As a** system,
**I want** tools to declare whether they execute in-app or in a container,
**So that** routing is explicit and not inferred from `kind`.

**Acceptance Criteria:**
- Migration adds `execution_mode` string column to `tools` (default: `"container"`)
- `Tool` model gains `enumerize :execution_mode, in: %i[app container], default: :container`
- `Tool#execute` routes based on `execution_mode`:
  - `:app` → `InternalToolExecutor.execute(self, parameters, session)`
  - `:container` → `start_container_execution(...)` (see Story 19.5)
- Existing seeds updated: workflow tools (`list_sub_steps`, `mark_sub_step`, `write_step_note`) get `execution_mode: :app`; `code_climate` gets `execution_mode: :container`
- Old routing logic based on `kind: :internal` removed from `Tool#execute`

**Technical notes:**
- `kind` (internal/custom) remains — it controls scoping and visibility, not execution
- `execution_mode` controls HOW the tool runs
- Default `:container` means existing custom tools work without migration

---

### Story 19.2: ToolResult Model + Uploader

**As a** system,
**I want** to persist container tool execution results in a dedicated model with Shrine attachments,
**So that** results are stored in S3 (not Temporal payloads) and delivered via presigned URLs.

**Acceptance Criteria:**
- Migration creates `tool_results` table:
  - `execution_id` (string, unique index, not null)
  - `state` (string, default `"processing"`, not null)
  - `tool_id` (references, not null)
  - `terminal_session_id` (references, optional)
  - `step_run_id` (references, optional)
  - `exit_code` (integer)
  - `error` (string)
  - `duration_ms` (integer)
  - Shrine columns: `stdout_data`, `stderr_data`, `result_data_data`, `output_data` (all text)
- `ToolResult` model with:
  - 4 Shrine attachments: `stdout`, `stderr`, `result_data`, `output`
  - `ToolResult.generate_id` → `"tr-#{SecureRandom.hex(12)}"`
  - `complete!(exit_code:, stdout:, stderr:, duration_ms:, error:)` — sets state, uploads non-empty strings as Shrine attachments, auto-parses JSON stdout into `result_data`
  - `attach_output_files(container, paths, runtime)` — reads files from container, packs tar.gz, attaches as `output`
  - States: `processing`, `completed`, `failed`, `expired`
  - Scope: `stale(age)` — completed/failed older than `age`
- `ToolResultUploader` with custom `generate_location`: `tool_results/{execution_id}/{attachment_name}/{filename}`
- Nil attachments left as nil (no empty uploads)

**Technical notes:**
- `result_data` is stdout parsed as JSON (if valid JSON hash/array). Useful for tools that output structured data (CodeClimate JSON)
- `output` is tar.gz archive of files collected from container (internal tools only)

---

### Story 19.3: ToolResult Serializer

**As a** system,
**I want** to serialize ToolResult for agent consumption with presigned download URLs,
**So that** agents receive compact metadata and download large files via curl.

**Acceptance Criteria:**
- `ToolResultSerializer < ApplicationSerializer` with attributes:
  - `execution_id`, `tool_name`, `state`, `exit_code`, `error`, `duration_ms`, `created_at`
  - For each attachment (stdout, stderr, result_data, output): `{name}_url` (presigned, 1h TTL) and `{name}_size`
- Nil attachments produce nil URL/size (serializer skips them naturally)
- Total serialized payload: ~200-400 bytes for typical result

**Technical notes:**
- Presigned URL TTL: 3600 seconds (1 hour)
- Agent can call `read_tool_result` again to get fresh URLs if expired
- URLs must be accessible from inside agent container — verify `Settings.container_asset_host` resolves for presigned S3/minio URLs

---

### Story 19.4: ToolStrategy Base Class

**As a** developer,
**I want** a shared base strategy for all tool container execution,
**So that** lifecycle phases (start, exec, timeout, persist, cleanup) are implemented once.

**Acceptance Criteria:**
- `ContainerStrategies::ToolStrategy < BaseStrategy` with:
  - `phase_config` — exec timeout from input, cleanup always runs
  - `start_container` — start without health check (tools run to completion)
  - `exec` — wait for container, collect logs, call `persist_result`, return tiny payload
  - `persist_result` — finds ToolResult by `input[:tool_result_id]`, calls `complete!`
  - `handle_timeout` — kills container, persists partial result with error message
  - Timeout: `[input[:timeout], MAX_TIMEOUT(1800)].min`
- Temporal activity result is always small: `{ tool_result_id:, exit_code:, status: }`
- All heavy data (stdout, stderr) goes to ToolResult → Shrine → S3

**Technical notes:**
- `ToolStrategy` does NOT collect files — that's `InternalToolStrategy`'s job in `before_cleanup`
- `CustomToolStrategy` and `InternalToolStrategy` both inherit from this

---

### Story 19.5: CustomToolStrategy

**As a** developer,
**I want** custom tool execution refactored into a ToolStrategy subclass,
**So that** it shares lifecycle logic with internal tools and persists results to ToolResult.

**Acceptance Criteria:**
- `ContainerStrategies::CustomToolStrategy < ToolStrategy`
- Data from Tool model: `resolve_image` → `tool.docker_image`, `build_cmd` → interpolated command + tool_files, `build_env_vars` → parameters as ENV + config_items + project env
- `build_host_config` → `build_host_config_with_limits` (Settings-based limits)
- **Security:** No bind mounts, no docker socket. Custom tools are sandboxed
- **Output:** Stdout/stderr only. No file collection from container
- All existing custom tool functionality preserved (command interpolation, tool_files setup, config_item resolution)
- Old `ToolExecutionStrategy` deleted after migration

**Technical notes:**
- Move private helpers (interpolate_command, file_setup_cmd, resolve_config_items) from old `ToolExecutionStrategy`
- No behavior changes for custom tools, only the result storage path changes (ToolResult instead of Temporal payload)

---

### Story 19.6: InternalToolStrategy with DSL

**As a** developer,
**I want** to define internal container tools declaratively via DSL blocks,
**So that** adding a new tool is ~15 lines instead of ~200.

**Acceptance Criteria:**
- `ContainerStrategies::InternalToolStrategy < ToolStrategy`
- `Definition` class with DSL methods: `image`, `timeout`, `memory`, `cpu_quota`, `working_dir`, `docker_socket!`, `output_files`, `cmd(&block)`, `env(&block)`, `binds(&block)`, `prepare(&block)`
- Class-level registry: `InternalToolStrategy.define(:name) { ... }` registers definition
- `InternalToolStrategy.build_for(name, params:, session:, tool_result_id:)` — resolves definition, runs prepare block, returns configured strategy instance
- `prepare` block runs before container creation — resolves repos, generates configs, etc. (Ruby code, not in container)
- `before_cleanup` collects `output_files` from container → packs → attaches to ToolResult
- **Security:** Per-definition. `docker_socket!` enables docker.sock mount. `binds` block can mount host paths. Only available for internal tools (definitions are code-reviewed)
- Code Climate definition migrated to DSL (first concrete tool)

**Technical notes:**
- `resolve_callable(val)` — if Proc, call with `input`; otherwise return as-is
- `defn.opts[:prepare]` receives `{ **params, session: }` hash, returns enriched hash
- DSL uses `tap` pattern for chainable setters

---

### Story 19.7: Code Climate as DSL Definition

**As a** developer,
**I want** Code Climate analysis defined via InternalToolStrategy DSL,
**So that** the separate CodeClimateStrategy and InternalTools::CodeClimate classes are eliminated.

**Acceptance Criteria:**
- `InternalToolStrategy.define :code_climate` block with:
  - Image: `codeclimate/codeclimate`, timeout: 600, memory: 2GB, cpu_quota: 100k
  - `docker_socket!` (Code Climate spawns engine sub-containers)
  - `prepare` block: resolve repository, ensure clone, generate `.codeclimate.yml`
  - `cmd` block: `["analyze", "-f", format, "-e", engines...]`
  - `env` block: `CODECLIMATE_CODE` pointing to repo path
  - `binds` block: repo read-only, docker socket, shared `/tmp/cc`
- Seed updated: `code_climate` tool gets `execution_mode: :container`
- Delete: `app/services/container_strategies/code_climate_strategy.rb`
- Delete: `app/services/internal_tools/code_climate.rb`
- Extract reusable helpers: `RepoCloneService.ensure_cloned(repo)`, `CodeClimateConfigWriter.ensure_config(repo_path, engines)`

**Technical notes:**
- `RepoCloneService` extracted from existing `InternalTools::CodeClimate#ensure_cloned` logic
- `CodeClimateConfigWriter` extracted from existing `ensure_config` logic

---

### Story 19.8: read_tool_result Internal Tool

**As an** agent,
**I want** to retrieve the status and download URLs for a tool execution result,
**So that** I can download and process tool outputs after async execution completes.

**Acceptance Criteria:**
- `InternalTools::ReadToolResult < Base` (execution_mode: `:app`)
- Parameter: `tool_result_id` (required string)
- Returns serialized ToolResult via `ToolResultSerializer` as JSON string
- If state is `processing`: returns metadata with `state: "processing"` (no URLs yet)
- If state is `completed`/`failed`: returns metadata with presigned URLs for all non-nil attachments
- If not found: returns error
- Tool seed:
  ```ruby
  Tool.find_or_create_by!(name: "read_tool_result", kind: :internal) do |t|
    t.display_name = "Read Tool Result"
    t.execution_mode = :app
    t.description = "Retrieve status and download URLs for an async tool execution. " \
                    "Returns presigned URLs valid for 1 hour. " \
                    "Download files using curl: curl -o result.json <url>"
    t.input_schema = {
      type: "object",
      properties: {
        tool_result_id: { type: "string", description: "Execution ID (e.g. tr-abc123...)" }
      },
      required: %w[tool_result_id]
    }
  end
  ```
- `read_tool_result` always available (not `workflow_only`), since container tools can run in any session

**Technical notes:**
- Agent workflow: call container tool → get `tr-xxx` → wait/retry `read_tool_result(tr-xxx)` until state != processing → `curl -o file <url>` → process file
- No special poll/wait mechanism. Agent decides when and how often to check

---

### Story 19.9: MCP Handler Update

**As a** system,
**I want** the MCP `tools/call` handler to create ToolResult and return execution_id for container tools,
**So that** container tools execute asynchronously and results are delivered via read_tool_result.

**Acceptance Criteria:**
- `execute_tool` in `action_mcp_dynamic_tools.rb` updated:
  - If `tool.execution_mode_app?` → sync execution, return result directly (no change)
  - If `tool.execution_mode_container?` → create `ToolResult(state: processing)`, call `tool.execute(tool_result_id:)`, return `{ exit_code: 0, stdout: execution_id }`
- `build_response_content` unchanged — works for both sync results and execution_id strings
- No sync/async switch based on timeout — all container tools are async

**Technical notes:**
- ToolResult creation happens in MCP handler (not in Tool#execute) because only MCP needs the execution_id return pattern
- Direct `Tool#execute` callers (tests, future API) can create ToolResult themselves if needed

---

### Story 19.10: ToolResult Cleanup Job

**As a** platform operator,
**I want** old tool results automatically cleaned up,
**So that** S3 storage doesn't grow unbounded.

**Acceptance Criteria:**
- `ToolResultCleanupJob < ApplicationJob`
- Retention period configurable via `Settings.tool_results.retention_days` (default: 30)
- Finds `completed`/`failed` ToolResults older than retention period
- Deletes Shrine attachments (stdout, stderr, result_data, output) from S3
- Sets state to `expired`, nulls all `*_data` columns
- Record itself preserved for audit trail (execution_id, exit_code, error, duration_ms)
- Job registered in Temporal schedules (daily)

**Technical notes:**
- No `expires_at` column — retention is global and configurable
- `processing` results older than 24h could indicate stuck executions — log warning but don't expire (separate monitoring concern)

---

### Story 19.11: Update Seeds and Migration

**As a** developer,
**I want** all tool seeds updated with `execution_mode` and new tools seeded,
**So that** the framework is ready after deploy.

**Acceptance Criteria:**
- Existing internal tool seeds updated:
  - `list_sub_steps`: `execution_mode: :app`
  - `mark_sub_step`: `execution_mode: :app`
  - `write_step_note`: `execution_mode: :app`
  - `code_climate`: `execution_mode: :container`
- New tool seed: `read_tool_result` (execution_mode: :app, kind: :internal)
- `read_tool_result` is NOT `workflow_only` — available in all sessions
- Migration: add `execution_mode` column to tools, default `"container"`
- Idempotent: all seeds use `find_or_create_by!`

---

### Story 19.12: Agent Context — Container Tool Usage Instructions

**As an** agent in a container,
**I want** clear instructions in my context file explaining how to work with container tools and tool results,
**So that** I know to expect an execution ID, poll with `read_tool_result`, and download via `curl`.

**Acceptance Criteria:**
- `SessionContextService#build_tool_descriptions` updated to group tools by execution mode and add usage instructions
- Context file includes a new section **"Tool Execution Modes"** before individual tool descriptions:

```markdown
## Tool Execution Modes

Tools on this platform work in two modes:

### Instant tools (execution_mode: app)
These return results directly in the MCP response. Use them normally.

### Container tools (execution_mode: container)
These run in Docker containers and may take seconds to minutes. They work asynchronously:

1. **Call the tool** — you receive an execution ID (e.g. `tr-a1b2c3d4e5f6`)
2. **Check status** — call `read_tool_result(tool_result_id: "tr-...")`.
   If `state` is `processing`, wait and try again.
   If `state` is `completed` or `failed`, proceed to step 3.
3. **Download results** — the response contains presigned URLs (`stdout_url`, `result_data_url`, etc.).
   Download them to local files:
   ```
   curl -sS -o /workspace/result.json "<result_data_url>"
   ```
4. **Process locally** — read and analyze the downloaded files as needed.

Important:
- NEVER expect container tool output directly in the MCP response — you only get an ID.
- Presigned URLs expire in 1 hour. Call `read_tool_result` again for fresh URLs if needed.
- `result_data_url` contains parsed JSON (if the tool output was valid JSON). Prefer it over `stdout_url`.
- `output_url` is a tar.gz archive of additional files collected from the tool container (if any).
```

- Each tool in the list shows its execution mode:
  ```markdown
  ### code_climate ⏳ container
  Code Climate Analysis — Run Code Climate static analysis on a repository.
  Returns: execution ID → use read_tool_result to get results
  Parameters: repository_id (integer), engines (string), format (string)

  ### list_sub_steps ⚡ app
  List Sub-Steps — List current step's sub-steps with their statuses.
  Returns: direct result
  ```
- `⚡ app` / `⏳ container` markers make it instantly clear to the agent which mode to expect
- `read_tool_result` tool description in the list includes a concise reminder:
  ```markdown
  ### read_tool_result ⚡ app
  Read Tool Result — Retrieve status and download URLs for an async tool execution.
  Returns: JSON with state, exit_code, presigned download URLs (stdout_url, result_data_url, output_url).
  Parameters: tool_result_id (string)
  ```

**Technical notes:**
- Changes are in `SessionContextService#build_tool_descriptions` only — no new methods needed
- The "Tool Execution Modes" section is static text, injected once before the tool list
- Only show the section if at least one container-mode tool is available in the session
- `tool.execution_mode` is already available on the Tool model after Story 19.1

---

### Story 19.13: Delete Legacy Code

**As a** developer,
**I want** replaced code removed,
**So that** there's no confusion about which execution path is active.

**Acceptance Criteria:**
- Delete `app/services/container_strategies/tool_execution_strategy.rb`
- Delete `app/services/container_strategies/code_climate_strategy.rb`
- Delete `app/services/internal_tools/code_climate.rb`
- Update all references to old strategy classes
- Update tests to use new strategies
- Verify: `Tool#execute` no longer references `ToolExecutionStrategy` or `CodeClimateStrategy`

---

## Dependency Graph

```
Story 19.1 (execution_mode on Tool)
    │
    ├──→ Story 19.2 (ToolResult model)
    │        │
    │        ├──→ Story 19.3 (Serializer)
    │        │
    │        └──→ Story 19.4 (ToolStrategy base)
    │                 │
    │                 ├──→ Story 19.5 (CustomToolStrategy)
    │                 │
    │                 └──→ Story 19.6 (InternalToolStrategy DSL)
    │                          │
    │                          └──→ Story 19.7 (Code Climate DSL definition)
    │
    ├──→ Story 19.8 (read_tool_result)
    │
    ├──→ Story 19.9 (MCP handler update)
    │
    └──→ Story 19.12 (Agent context instructions) — after 19.1

Story 19.10 (Cleanup job) — independent
Story 19.11 (Seeds) — after 19.1, 19.8
Story 19.13 (Delete legacy) — after all above
```

---

## Implementation Notes

- `InternalToolExecutor` and `InternalTools::Base` stay — they handle `app`-mode tools (list_sub_steps, mark_sub_step, write_step_note, read_tool_result)
- Epic 18 stories 18.1–18.5 (router, visibility, workflow tools) already implemented — this epic does not change them
- Epic 18 story 18.6 (Code Climate) is superseded by 19.7 (DSL definition)
- No frontend changes — tools appear automatically via MCP, ToolResult is backend-only
- Presigned URLs require container-accessible S3/minio host — verify `Settings.container_asset_host` works with Shrine's `url(expires_in:)`
- `TarGzPacker` utility needed for `attach_output_files` — small helper class or use `Gem::Package::TarWriter` + `Zlib::GzipWriter`

---
