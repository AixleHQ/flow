# Story 16.10: Migrate Existing Session Config Data

Status: ready-for-dev

## Story

As a platform engineer,
I want existing `session_config` JSONB data migrated to the new join tables and columns,
so that the transition is seamless and no data is lost.

## Acceptance Criteria

1. **AC1: Data migration** — Ruby migration that for each `TerminalSession` with non-empty `session_config`:
   - `tool_ids` → inserts into `session_tools` (skip IDs where Tool no longer exists)
   - `skill_ids` → inserts into `session_skills`
   - `mcp_server_ids` → inserts into `session_mcp_servers`
   - `asset_ids` → inserts into `session_input_assets`
   - `repository_ids` → inserts into `session_repositories`
   - `agent_id` → sets `configured_agent_id`
   - `mode` → sets `mode` column
   - `initial_prompt` → sets `initial_prompt` column

2. **AC2: JSONB cleanup** — After migrating each session, remove migrated keys from `session_config`, keeping only `config_files` and `env_vars`.

3. **AC3: Idempotent** — Migration can run multiple times safely (skip if join records already exist, use `INSERT ... ON CONFLICT DO NOTHING`).

4. **AC4: Batched** — Process in batches of 500 to avoid memory issues.

5. **AC5: Orphan handling** — Skip IDs that reference deleted entities (Tool, Skill, etc.) without failing.

## Tasks / Subtasks

- [ ] Task 1: Create data migration (AC: #1, #2, #3, #4, #5)
  - [ ] 1.1 Create migration `MigrateSessionConfigToJoinTables`
  - [ ] 1.2 Batch query: `TerminalSession.where.not(session_config: {}).in_batches(of: 500)`
  - [ ] 1.3 For each session: extract IDs from JSONB, insert into join tables
  - [ ] 1.4 Set scalar columns: `configured_agent_id`, `mode`, `initial_prompt`
  - [ ] 1.5 Clean up `session_config`: remove migrated keys, keep `config_files` and `env_vars`
  - [ ] 1.6 Use raw SQL for join table inserts (performance)
- [ ] Task 2: Add reversibility
  - [ ] 2.1 Implement `down` method that copies join table data back to JSONB
- [ ] Task 3: Write verification
  - [ ] 3.1 After migration, verify counts match: `session_tools.count` vs sum of `session_config["tool_ids"].length`

## Dev Notes

### Migration Implementation

```ruby
class MigrateSessionConfigToJoinTables < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  MIGRATED_KEYS = %w[tool_ids skill_ids mcp_server_ids asset_ids repository_ids agent_id mode initial_prompt].freeze
  BATCH_SIZE = 500

  def up
    existing_tools = Tool.pluck(:id).to_set
    existing_skills = Skill.pluck(:id).to_set
    existing_mcp_servers = MCPServer.pluck(:id).to_set
    existing_assets = Asset.pluck(:id).to_set
    existing_repositories = Repository.pluck(:id).to_set
    existing_agents = Agent.pluck(:id).to_set

    TerminalSession.where.not(session_config: {}).in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |session|
        config = session.session_config
        next if config.blank?

        migrate_join_table(session.id, config["tool_ids"], :session_tools, :tool_id, existing_tools)
        migrate_join_table(session.id, config["skill_ids"], :session_skills, :skill_id, existing_skills)
        migrate_join_table(session.id, config["mcp_server_ids"], :session_mcp_servers, :mcp_server_id, existing_mcp_servers)
        migrate_join_table(session.id, config["asset_ids"], :session_input_assets, :asset_id, existing_assets)
        migrate_join_table(session.id, config["repository_ids"], :session_repositories, :repository_id, existing_repositories)

        updates = {}
        if config["agent_id"].present? && existing_agents.include?(config["agent_id"])
          updates[:configured_agent_id] = config["agent_id"]
        end
        updates[:mode] = config["mode"] if config["mode"].present?
        updates[:initial_prompt] = config["initial_prompt"] if config["initial_prompt"].present?

        cleaned_config = config.except(*MIGRATED_KEYS)
        updates[:session_config] = cleaned_config

        session.update_columns(updates) if updates.any?
      end
    end
  end

  def down
    TerminalSession.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |session|
        config = session.session_config || {}

        config["tool_ids"] = session_join_ids(:session_tools, :tool_id, session.id)
        config["skill_ids"] = session_join_ids(:session_skills, :skill_id, session.id)
        config["mcp_server_ids"] = session_join_ids(:session_mcp_servers, :mcp_server_id, session.id)
        config["asset_ids"] = session_join_ids(:session_input_assets, :asset_id, session.id)
        config["repository_ids"] = session_join_ids(:session_repositories, :repository_id, session.id)
        config["agent_id"] = session.configured_agent_id if session.configured_agent_id.present?
        config["mode"] = session.mode if session.mode != "interactive"
        config["initial_prompt"] = session.initial_prompt if session.initial_prompt.present?

        session.update_columns(
          session_config: config,
          configured_agent_id: nil,
          mode: "interactive",
          initial_prompt: nil
        )
      end
    end

    %i[session_tools session_skills session_mcp_servers session_input_assets session_repositories].each do |table|
      execute("DELETE FROM #{table}")
    end
  end

  private

  def migrate_join_table(session_id, ids, table_name, fk_column, valid_ids)
    return if ids.blank?

    valid = ids.select { |id| valid_ids.include?(id) }
    return if valid.empty?

    values = valid.map { |id| "(#{session_id}, #{id})" }.join(", ")
    execute(<<~SQL)
      INSERT INTO #{table_name} (terminal_session_id, #{fk_column})
      VALUES #{values}
      ON CONFLICT DO NOTHING
    SQL
  end

  def session_join_ids(table_name, fk_column, session_id)
    result = execute("SELECT #{fk_column} FROM #{table_name} WHERE terminal_session_id = #{session_id}")
    result.map { |row| row[fk_column.to_s] }
  end
end
```

### Key Decisions

1. **`disable_ddl_transaction!`** — Data migration runs outside DDL transaction for performance on large datasets.

2. **Pre-load valid IDs** — Load all existing entity IDs upfront (`Tool.pluck(:id).to_set`) to avoid N+1 existence checks. For a typical deployment, these sets are small (hundreds to low thousands).

3. **`ON CONFLICT DO NOTHING`** — Makes migration idempotent. Running twice won't duplicate join records.

4. **`update_columns`** — Bypasses validations and callbacks (we're migrating data, not changing business state). Faster than `update!`.

5. **Cleaned session_config** — After migration, `session_config` only contains `config_files` and `env_vars`. Empty hash `{}` if neither exists.

### Verification Query

Run after migration to verify:

```sql
-- Check for sessions where JSONB still has migrated keys
SELECT id, session_config
FROM terminal_sessions
WHERE session_config ? 'tool_ids'
   OR session_config ? 'skill_ids'
   OR session_config ? 'mcp_server_ids'
   OR session_config ? 'asset_ids'
   OR session_config ? 'repository_ids'
   OR session_config ? 'agent_id'
   OR session_config ? 'mode'
   OR session_config ? 'initial_prompt';
-- Should return 0 rows
```

### Performance Estimate

With ~1000 terminal sessions (typical for early platform), migration takes <10 seconds. For larger datasets, the batch processing ensures memory stays bounded.

### Files to Touch

- `web/db/migrate/YYYYMMDD_migrate_session_config_to_join_tables.rb` (new)

### Dependencies

- **Requires Story 16.9** — Join tables and columns must exist

### What NOT To Change

- Do NOT remove JSONB accessor methods yet — that's Story 16.11
- Do NOT update services or controllers — that's Story 16.11
- Keep `session_config` column for `config_files` and `env_vars`

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.10]
- [Source: web/app/models/terminal_session.rb — ALLOWED_SESSION_CONFIG_KEYS and accessor methods]
- [Source: web/db/schema.rb — terminal_sessions table]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
