# Story 16.9: Session Config Join Tables

Status: ready-for-dev

## Story

As a platform engineer,
I want session configuration stored in proper join tables with foreign keys,
so that deleting a tool/skill/MCP server automatically cleans up session references instead of leaving orphaned IDs in JSON.

## Acceptance Criteria

1. **AC1: Join tables migration** — Create 5 join tables with FK constraints:
   - `session_tools` (terminal_session_id, tool_id) — unique composite index, FK ON DELETE CASCADE
   - `session_skills` (terminal_session_id, skill_id) — unique composite index, FK ON DELETE CASCADE
   - `session_mcp_servers` (terminal_session_id, mcp_server_id) — unique composite index, FK ON DELETE CASCADE
   - `session_input_assets` (terminal_session_id, asset_id) — unique composite index, FK ON DELETE CASCADE
   - `session_repositories` (terminal_session_id, repository_id) — unique composite index, FK ON DELETE CASCADE

2. **AC2: Scalar columns migration** — Add to `terminal_sessions`:
   - `configured_agent_id` (bigint, nullable, FK → agents, ON DELETE SET NULL)
   - `mode` (string, default `"interactive"`)
   - `initial_prompt` (text, nullable)

3. **AC3: HABTM relations** — `TerminalSession` gets:
   - `has_and_belongs_to_many :tools, join_table: :session_tools`
   - `has_and_belongs_to_many :skills, join_table: :session_skills`
   - `has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers`
   - `has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets`
   - `has_and_belongs_to_many :repositories, join_table: :session_repositories`
   - `belongs_to :configured_agent, class_name: "Agent", optional: true`

4. **AC4: FK CASCADE** — Deleting a Tool removes all `session_tools` rows referencing it. Deleting an Agent nullifies `configured_agent_id`. No orphaned data.

5. **AC5: config_files/env_vars preserved** — `session_config` JSONB column remains for `config_files` and `env_vars` (dynamic key-value data).

## Tasks / Subtasks

- [ ] Task 1: Create join tables migration (AC: #1)
  - [ ] 1.1 Create `session_tools` table (no PK, composite unique index)
  - [ ] 1.2 Create `session_skills` table
  - [ ] 1.3 Create `session_mcp_servers` table
  - [ ] 1.4 Create `session_input_assets` table
  - [ ] 1.5 Create `session_repositories` table
  - [ ] 1.6 Add FK constraints with `on_delete: :cascade` on all join tables
- [ ] Task 2: Create scalar columns migration (AC: #2)
  - [ ] 2.1 Add `configured_agent_id` with FK on_delete: :nullify
  - [ ] 2.2 Add `mode` string column default "interactive"
  - [ ] 2.3 Add `initial_prompt` text column
- [ ] Task 3: Add HABTM relations (AC: #3)
  - [ ] 3.1 Add all 5 HABTM declarations to TerminalSession
  - [ ] 3.2 Add `belongs_to :configured_agent`
  - [ ] 3.3 Ensure `mode` and `initial_prompt` accessors work from columns (not JSONB)
- [ ] Task 4: Test FK constraints (AC: #4)
  - [ ] 4.1 Test: deleting a Tool cascade-removes session_tools records
  - [ ] 4.2 Test: deleting an Agent nullifies configured_agent_id
  - [ ] 4.3 Test: deleting a Skill cascade-removes session_skills records
  - [ ] 4.4 Test: deleting an MCP server cascade-removes session_mcp_servers records

## Dev Notes

### Migration — Join Tables

```ruby
class CreateSessionConfigJoinTables < ActiveRecord::Migration[8.1]
  def change
    create_table :session_tools, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :tool, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_tools, [:terminal_session_id, :tool_id], unique: true

    create_table :session_skills, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :skill, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_skills, [:terminal_session_id, :skill_id], unique: true

    create_table :session_mcp_servers, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :mcp_server, null: false, foreign_key: { to_table: :mcp_servers, on_delete: :cascade }, index: false
    end
    add_index :session_mcp_servers, [:terminal_session_id, :mcp_server_id], unique: true

    create_table :session_input_assets, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :asset, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_input_assets, [:terminal_session_id, :asset_id], unique: true

    create_table :session_repositories, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :repository, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_repositories, [:terminal_session_id, :repository_id], unique: true
  end
end
```

### Migration — Scalar Columns

```ruby
class AddNormalizedConfigToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :terminal_sessions, :configured_agent, null: true,
                  foreign_key: { to_table: :agents, on_delete: :nullify }
    add_column :terminal_sessions, :mode, :string, default: "interactive"
    add_column :terminal_sessions, :initial_prompt, :text
  end
end
```

### HABTM Relations on TerminalSession

```ruby
# Join-table relations (replacing JSONB arrays)
has_and_belongs_to_many :tools, join_table: :session_tools
has_and_belongs_to_many :skills, join_table: :session_skills
has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers
has_and_belongs_to_many :input_assets, class_name: "Asset", join_table: :session_input_assets
has_and_belongs_to_many :repositories, join_table: :session_repositories
belongs_to :configured_agent, class_name: "Agent", optional: true
```

### MCPServer Table Name

The `mcp_servers` table's model class is `MCPServer` (not `McpServer`). The FK reference uses `to_table: :mcp_servers` explicitly. The HABTM declaration `has_and_belongs_to_many :mcp_servers` should work because Rails infers table name from the association name. If issues arise with class resolution, add `class_name: "MCPServer"`:

```ruby
has_and_belongs_to_many :mcp_servers, join_table: :session_mcp_servers, class_name: "MCPServer"
```

### Why HABTM (not has_many :through)

HABTM is simpler when the join table has no extra attributes. These tables only store the pair of IDs — no timestamps, no metadata. HABTM gives us `tool_ids`, `tool_ids=`, `tools`, `tools<<` methods for free.

If extra attributes are ever needed (e.g., "order" or "added_at"), switch to `has_many :through`.

### Dual Accessor Period

During the migration period (before Story 16.10 migrates data and Story 16.11 removes JSONB accessors), both old JSONB accessors (`session_config["tool_ids"]`) and new HABTM accessors (`tools.pluck(:id)`) will coexist. Story 16.11 removes the old ones.

### mode Column vs JSONB mode

After adding `mode` column, there will be a name conflict with the existing `def mode` accessor that reads from `session_config["mode"]`. In this story, we only add the column and relations. The JSONB accessor removal happens in Story 16.11. During the transition, the JSONB accessor takes precedence (it's a method that overrides column accessor). This is intentional — existing code continues to work until 16.11 switches over.

### Files to Touch

- `web/db/migrate/YYYYMMDD_create_session_config_join_tables.rb` (new)
- `web/db/migrate/YYYYMMDD_add_normalized_config_to_terminal_sessions.rb` (new)
- `web/app/models/terminal_session.rb` — add HABTM declarations and belongs_to
- `web/test/models/terminal_session_test.rb` — FK cascade tests

### Dependencies

None — this is a foundational migration.

### What NOT To Change

- Do NOT remove JSONB accessor methods — that's Story 16.11
- Do NOT migrate existing data — that's Story 16.10
- Do NOT update controllers or services — that's Story 16.11
- Do NOT update serializer — that's Story 16.11

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.9]
- [Source: web/app/models/terminal_session.rb — current JSONB accessors]
- [Source: web/db/schema.rb — terminal_sessions table definition]
- [Source: web/app/models/tool.rb — Tool model for FK reference]
- [Source: web/app/models/skill.rb — Skill model]
- [Source: web/app/models/mcp_server.rb — MCPServer model (note uppercase class name)]
- [Source: web/app/models/agent.rb — Agent model]
- [Source: web/app/models/repository.rb — Repository model]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
