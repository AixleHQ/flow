# Story 29.2: Additive Resource Resolution (Tools, Skills, MCP Servers)

Status: done

## Story

As a system,
I want the resolver to additively merge tools, skills, and MCP servers from Workflow base + Step,
So that workflow-level base resources are available in every step alongside step-specific ones.

## Acceptance Criteria

1. **Tool union** — Given a Workflow with `config["base_tool_ids"] = [1, 2]` and Step with `tool_ids = [2, 3]`, when resolver resolves tool_ids, then result is `[1, 2, 3]` (union, deduplicated)

2. **Skill union** — Given a Workflow with `config["base_skill_ids"] = [10]` and Step with `skill_ids = [11]`, when resolver resolves skill_ids, then result is `[10, 11]`

3. **MCP union** — Given a Workflow with `config["base_mcp_server_ids"] = [20]` and Step with `mcp_server_ids = []`, when resolver resolves mcp_server_ids, then result is `[20]` (workflow base present even when step has none)

4. **Standalone pass-through** — Given a standalone session with `tool_ids = [5, 6]`, when resolver resolves tool_ids, then result is `[5, 6]` (no merging)

5. **Workflow helper methods** — Workflow model exposes `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids` reading from `config` jsonb, returning `[]` when absent

6. **Empty base** — Given a Workflow with no base resource IDs in config and Step with `tool_ids = [7]`, when resolver runs, then result is `[7]` (empty base is graceful)

## Tasks / Subtasks

- [ ] Task 1: Add Workflow helper methods (AC: #5)
  - [ ] Add `base_tool_ids` method to Workflow: `config&.dig("base_tool_ids") || []`
  - [ ] Add `base_skill_ids` method: `config&.dig("base_skill_ids") || []`
  - [ ] Add `base_mcp_server_ids` method: `config&.dig("base_mcp_server_ids") || []`
- [ ] Task 2: Implement additive resolution in SessionConfigResolver (AC: #1, #2, #3, #6)
  - [ ] `resolve_tool_ids`: `(workflow.base_tool_ids + step.tool_ids).uniq` for workflow sessions
  - [ ] `resolve_skill_ids`: `(workflow.base_skill_ids + step.skill_ids).uniq`
  - [ ] `resolve_mcp_server_ids`: `(workflow.base_mcp_server_ids + step.mcp_server_ids).uniq`
  - [ ] Handle nil/empty gracefully with `|| []`
- [ ] Task 3: Verify standalone pass-through (AC: #4)
  - [ ] Standalone branches must remain unchanged — return session's own IDs
- [ ] Task 4: Write tests (AC: #1-#6)
  - [ ] Test Workflow `base_tool_ids` returns from config jsonb
  - [ ] Test Workflow `base_tool_ids` returns `[]` when config is nil
  - [ ] Test additive union with overlap → deduplicated
  - [ ] Test additive union when step has empty → workflow base still returned
  - [ ] Test standalone pass-through unchanged

## Dev Notes

### Architecture Patterns

- **Additive, not override** — core principle of the config cascade. Resources accumulate from every level; no level can remove resources added by another
- **Step.tool_ids** is a postgres array column (integer[]) on the `steps` table. Read directly as `step.tool_ids`
- **Workflow.config** is a jsonb column. Base resource IDs are stored as arrays under keys like `"base_tool_ids"`. No migration needed — existing jsonb is used
- Pattern: `(workflow.base_X_ids + step.X_ids).uniq`

### Existing Code Context

- `Workflow` model (app/models/workflow.rb) — has `config` jsonb, currently used for misc settings. No `base_*_ids` helpers yet
- `Step` model (app/models/step.rb) — has `tool_ids`, `skill_ids`, `mcp_server_ids` as postgres array columns
- `LaunchStepSessionActivity#attach_resources!` — currently reads only from `step.tool_ids`, `step.skill_ids`, `step.mcp_server_ids`. Does NOT read workflow base. This is the gap being fixed

### File Locations

- Modified: `app/models/workflow.rb` — add 3 helper methods
- Modified: `app/services/session_config_resolver.rb` — update resolve methods
- Modified: `test/services/session_config_resolver_test.rb` — add test cases
- New test (optional): `test/models/workflow_test.rb` — test base_*_ids helpers

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb test/models/workflow_test.rb`
- Use workflow factory with `config: { "base_tool_ids" => [1, 2] }` to test helpers

### References

- [Source: ai/session-config-cascade.md#3.3] — Additive tool/skill/MCP resolution pattern
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.2] — AC and technical notes
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb#56-76] — Current step-only attachment (gap)
- [Source: app/models/workflow.rb] — Workflow model, config jsonb

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
