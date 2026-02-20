# Story 16.11: Update Services & API for Normalized Config

Status: ready-for-dev

## Story

As a platform engineer,
I want all services and API endpoints to use the new join-table relations instead of JSONB,
so that the codebase is consistent and the old accessors are removed.

## Acceptance Criteria

1. **AC1: Remove JSONB accessors** — Delete `ALLOWED_SESSION_CONFIG_KEYS`, `tool_ids`, `skill_ids`, `mcp_server_ids`, `asset_ids`, `repository_ids`, `configured_agent_id` (JSONB version), `mode` (JSONB version), `initial_prompt` (JSONB version) accessor methods from `TerminalSession`.

2. **AC2: Remove JSONB validators** — Delete `validate_session_config` and `validate_non_interactive_prompt` methods. Replace with proper relation-based validations.

3. **AC3: SessionContextService** — Update all references to use HABTM relations:
   - `session.tool_ids` → `session.tool_ids` (now from HABTM)
   - `session.mcp_server_ids` → `session.mcp_server_ids` (HABTM)
   - `session.skill_ids` → `session.skill_ids` (HABTM)
   - `session.asset_ids` → `session.input_asset_ids` (HABTM)
   - `session.repository_ids` → `session.repository_ids` (HABTM)
   - `session.configured_agent_id` → `session.configured_agent_id` (column)
   - `session.mode` → `session.mode` (column)
   - `session.initial_prompt` → `session.initial_prompt` (column)

4. **AC4: Controller update** — Terminal sessions controller create/update accepts relation IDs as top-level params (`tool_ids`, `skill_ids`, etc.) and assigns through HABTM. `session_config` only accepts `config_files` and `env_vars`.

5. **AC5: Serializer update** — `TerminalSessionSerializer` returns:
   - `tool_ids`, `skill_ids`, `mcp_server_ids`, `input_asset_ids`, `repository_ids` as top-level arrays
   - `configured_agent_id`, `mode`, `initial_prompt` as top-level fields
   - `session_config` only contains `config_files` and `env_vars`

6. **AC6: Frontend types** — Update `ITerminalSession` and `ISessionConfig`. Config only has `configFiles` and `envVars`. Relation IDs are top-level. Update `ICreateTerminalSessionRequest`.

7. **AC7: Frontend form** — Update `CompanySessionNewPage` / `SessionLaunchWidget` to submit relation IDs at top level.

8. **AC8: available_tools** — Update method to use `self.tools` relation instead of `Tool.where(id: tool_ids)`.

## Tasks / Subtasks

- [ ] Task 1: Remove JSONB accessors and validators (AC: #1, #2)
  - [ ] 1.1 Delete all JSONB accessor methods (tool_ids, skill_ids, etc.)
  - [ ] 1.2 Delete `ALLOWED_SESSION_CONFIG_KEYS`
  - [ ] 1.3 Delete `validate_session_config`
  - [ ] 1.4 Delete `validate_non_interactive_prompt`
  - [ ] 1.5 Add: `validates :mode, inclusion: { in: %w[interactive non_interactive] }`
  - [ ] 1.6 Add: `validates :initial_prompt, presence: true, if: -> { mode == "non_interactive" }`
- [ ] Task 2: Update available_tools method (AC: #8)
  - [ ] 2.1 Change from `Tool.where(id: tool_ids).enabled` to `tools.enabled`
  - [ ] 2.2 Keep fallback to project tools if `tools.empty?`
- [ ] Task 3: Update SessionContextService (AC: #3)
  - [ ] 3.1 Find all reads of `session.asset_ids` → change to `session.input_asset_ids`
  - [ ] 3.2 Verify all other accessors work via HABTM (tool_ids, skill_ids, etc.)
  - [ ] 3.3 Update `session.configured_agent_id` references (now column, same API)
  - [ ] 3.4 Update config_files/env_vars access: `session.session_config["config_files"]` (stays same)
- [ ] Task 4: Update AgentSessionStrategy (AC: #3)
  - [ ] 4.1 Update `build_env_vars` to use `session.mode` (column) and `session.initial_prompt` (column)
  - [ ] 4.2 Update `ttyd_command` similarly
  - [ ] 4.3 These should work without changes since column accessors have same names
- [ ] Task 5: Update controller (AC: #4)
  - [ ] 5.1 Find terminal sessions controller (likely `Api::V1::TerminalSessionsController`)
  - [ ] 5.2 Update `create` params to accept `tool_ids`, `skill_ids`, `mcp_server_ids`, `input_asset_ids`, `repository_ids`, `configured_agent_id`, `mode`, `initial_prompt` at top level
  - [ ] 5.3 Assign HABTM: `session.tool_ids = params[:tool_ids]` etc.
  - [ ] 5.4 `session_config` params only accept `config_files`, `env_vars`
- [ ] Task 6: Update serializer (AC: #5)
  - [ ] 6.1 Add `tool_ids`, `skill_ids`, `mcp_server_ids`, `input_asset_ids`, `repository_ids` methods
  - [ ] 6.2 Add `configured_agent_id`, `mode`, `initial_prompt` to attributes
  - [ ] 6.3 Update `session_config` to only return `config_files` and `env_vars`
- [ ] Task 7: Update frontend types (AC: #6)
  - [ ] 7.1 Move `toolIds`, `skillIds`, `mcpServerIds`, `repositoryIds` from `ISessionConfig` to `ITerminalSession`
  - [ ] 7.2 Add `inputAssetIds`, `configuredAgentId`, `mode`, `initialPrompt` to `ITerminalSession`
  - [ ] 7.3 `ISessionConfig` becomes `{ configFiles?: Record<string, string>; envVars?: Record<string, string> }`
  - [ ] 7.4 Update `ICreateTerminalSessionRequest` to match new API shape
- [ ] Task 8: Update frontend form (AC: #7)
  - [ ] 8.1 Find and update `SessionLaunchWidget` to submit top-level IDs
  - [ ] 8.2 Update any form that creates sessions
- [ ] Task 9: Update tests
  - [ ] 9.1 Update model tests: remove JSONB config tests, add HABTM tests
  - [ ] 9.2 Update controller tests: new param format
  - [ ] 9.3 Update strategy tests: verify accessors work
  - [ ] 9.4 Update SessionContextService tests if they exist

## Dev Notes

### TerminalSession Model — Before vs After

**Before (JSONB):**
```ruby
ALLOWED_SESSION_CONFIG_KEYS = %w[config_files env_vars mcp_server_ids tool_ids agent_id skill_ids asset_ids repository_ids mode initial_prompt].freeze

def tool_ids
  session_config["tool_ids"] || []
end
# ... 8 more accessors
```

**After (relations + columns):**
```ruby
has_and_belongs_to_many :tools, join_table: :session_tools
has_and_belongs_to_many :skills, join_table: :session_skills
has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers, class_name: "MCPServer"
has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets
has_and_belongs_to_many :repositories, join_table: :session_repositories
belongs_to :configured_agent, class_name: "Agent", optional: true

# mode and initial_prompt are now DB columns (from Story 16.9 migration)
validates :mode, inclusion: { in: %w[interactive non_interactive] }, allow_nil: true
validates :initial_prompt, presence: true, if: -> { mode == "non_interactive" }

def config_files
  session_config["config_files"] || {}
end

def env_vars
  session_config["env_vars"] || {}
end
```

### HABTM gives us tool_ids for free

Rails HABTM automatically provides:
- `session.tool_ids` → returns array of IDs
- `session.tool_ids = [1, 2, 3]` → sets the association (bulk assignment)
- `session.tools` → returns relation
- `session.tools << tool` → adds to association

This means most existing code that calls `session.tool_ids` will work unchanged after removing the JSONB accessor — HABTM provides the same-named method.

### asset_ids → input_asset_ids rename

The old `session.asset_ids` accessor (from JSONB) needs to change to `session.input_asset_ids` to distinguish from `session.output_assets` (Story 16.4). HABTM with `input_assets` association gives `input_asset_ids`.

Search for all `session.asset_ids` references and update:
- `SessionContextService` — asset injection logic
- Controller — create params
- Serializer — output
- Frontend — types and form

### Controller Changes

Find the create action. Currently accepts:
```json
{
  "terminal_session": {
    "session_config": {
      "tool_ids": [1, 2],
      "skill_ids": [3],
      "mode": "interactive"
    }
  }
}
```

Changes to:
```json
{
  "terminal_session": {
    "tool_ids": [1, 2],
    "skill_ids": [3],
    "mode": "interactive",
    "session_config": {
      "config_files": { ... },
      "env_vars": { ... }
    }
  }
}
```

### Serializer Changes

```ruby
attributes :tool_ids, :skill_ids, :mcp_server_ids, :input_asset_ids,
           :repository_ids, :configured_agent_id, :mode, :initial_prompt

def tool_ids
  object.tool_ids
end

def skill_ids
  object.skill_ids
end

def mcp_server_ids
  object.mcp_server_ids
end

def input_asset_ids
  object.input_asset_ids
end

def repository_ids
  object.repository_ids
end

def session_config
  {
    "config_files" => object.config_files,
    "env_vars" => object.env_vars
  }.compact_blank
end
```

### Frontend Type Changes

```typescript
export interface ISessionConfig {
  configFiles?: Record<string, string>;
  envVars?: Record<string, string>;
}

export interface ITerminalSession {
  // ... existing fields ...
  toolIds: number[];
  skillIds: number[];
  mcpServerIds: number[];
  inputAssetIds: number[];
  repositoryIds: number[];
  configuredAgentId: number | null;
  mode: SessionMode;
  initialPrompt: string | null;
  sessionConfig: ISessionConfig | null;
  // ... usage fields ...
}

export interface ICreateTerminalSessionRequest {
  terminalSession: {
    sessionType: TerminalSessionType;
    agentType: AgentType;
    projectId?: number;
    toolIds?: number[];
    skillIds?: number[];
    mcpServerIds?: number[];
    inputAssetIds?: number[];
    repositoryIds?: number[];
    configuredAgentId?: number;
    mode?: SessionMode;
    initialPrompt?: string;
    sessionConfig?: ISessionConfig;
    metadata?: Record<string, unknown>;
  };
}
```

### Breaking Change Management

This is an API breaking change. Since frontend and backend deploy together (monorepo), coordinate:
1. Deploy backend + frontend in same release
2. Frontend sends new format
3. Backend accepts new format

### SessionContextService Impact

`SessionContextService` has these key methods that read session config:
- `resolve_env_vars(session)` — reads `session.env_vars` (stays JSONB, no change)
- `resolve_config_files(session)` — reads `session.config_files` (stays JSONB, no change)
- `resolve_tools(session)` — reads `session.tool_ids` (HABTM now, same API)
- `resolve_mcp_servers(session)` — reads `session.mcp_server_ids` (HABTM now, same API)
- `resolve_skills(session)` — reads `session.skill_ids` (HABTM now, same API)
- `inject_assets(session)` — reads `session.asset_ids` → **change to `session.input_asset_ids`**
- `inject_repositories(session)` — reads `session.repository_ids` (HABTM now, same API)

Most methods work unchanged. Only `asset_ids` → `input_asset_ids` needs explicit update.

### Files to Touch

- `web/app/models/terminal_session.rb` — remove JSONB accessors, update validations
- `web/app/services/session_context_service.rb` — `asset_ids` → `input_asset_ids`
- `web/app/services/container_strategies/agent_session_strategy.rb` — verify mode/initial_prompt work
- `web/app/controllers/api/v1/terminal_sessions_controller.rb` — update create params
- `web/app/serializers/terminal_session_serializer.rb` — new top-level fields
- `web/app/frontend/entities/terminal-session/model/types.ts` — reshape types
- `web/app/frontend/widgets/session-launch/` — update form submission
- `web/app/frontend/entities/terminal-session/ui/SessionSummaryCard.tsx` — update config reads
- Various test files

### Dependencies

- **Requires Story 16.9** — Join tables and columns exist
- **Requires Story 16.10** — Data migrated from JSONB to join tables

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.11]
- [Source: web/app/models/terminal_session.rb — JSONB accessors lines 49-91, validators lines 121-141]
- [Source: web/app/services/session_context_service.rb — session config reads]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — build_env_vars, ttyd_command]
- [Source: web/app/serializers/terminal_session_serializer.rb — session_config attribute]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — ISessionConfig interface]
- [Source: web/app/frontend/entities/terminal-session/ui/SessionSummaryCard.tsx — reads config.toolIds etc.]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
