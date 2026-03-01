# Story 29.3: Workflow `inherit_all_project_resources` Flag

Status: done

## Story

As a system,
I want a Workflow flag `inherit_all_project_resources` that includes all project-level tools, skills, and MCP servers,
So that auto-triggered workflows from the board can have full access to project resources without manually configuring each.

## Acceptance Criteria

1. **Inherit all — tools** — Given a Workflow with `config["inherit_all_project_resources"] = true` and a Project with tools `[1..5]`, when resolver resolves tool_ids, then result includes all project tools plus workflow base plus step tools (union, deduplicated)

2. **Inherit off — tools** — Given a Workflow with `inherit_all_project_resources = false`, when resolver resolves tool_ids, then result includes only workflow base + step tools (no project-level injection)

3. **Inherit all additive with step** — Given `inherit_all = true` and Step with additional tools `[6]`, when resolver resolves, then step tools are added on top of project tools

4. **Inherit all — skills** — Given `inherit_all = true`, when resolver resolves skill_ids, then all `Skill.merged_for_project(project)` IDs are included in the union

5. **Inherit all — MCP servers** — Given `inherit_all = true`, when resolver resolves mcp_server_ids, then all `MCPServer.merged_for_project(project)` IDs are included in the union

6. **Default false** — Given a Workflow with no `inherit_all_project_resources` in config, when resolver checks, then it defaults to `false`

7. **Standalone unaffected** — Standalone sessions are not affected by this flag

## Tasks / Subtasks

- [ ] Task 1: Add Workflow helper method (AC: #6)
  - [ ] Add `inherit_all_project_resources` method: `config&.dig("inherit_all_project_resources") || false`
- [ ] Task 2: Update resolver resolution methods (AC: #1, #2, #3, #4, #5)
  - [ ] In `resolve_tool_ids`: prepend `project_tool_ids` when `workflow.inherit_all_project_resources`
  - [ ] In `resolve_skill_ids`: prepend `project_skill_ids` when inherit_all
  - [ ] In `resolve_mcp_server_ids`: prepend `project_mcp_server_ids` when inherit_all
  - [ ] Helper: `project_tool_ids` → `Tool.merged_for_project(project).pluck(:id)`
  - [ ] Helper: `project_skill_ids` → `Skill.merged_for_project(project).pluck(:id)`
  - [ ] Helper: `project_mcp_server_ids` → `MCPServer.merged_for_project(project).pluck(:id)`
- [ ] Task 3: Write tests (AC: #1-#7)
  - [ ] Test inherit_all=true includes project tools + workflow base + step
  - [ ] Test inherit_all=false excludes project tools
  - [ ] Test inherit_all=true with skills
  - [ ] Test inherit_all=true with MCP servers
  - [ ] Test default false when key missing from config
  - [ ] Test standalone unaffected

## Dev Notes

### Architecture Patterns

- **`merged_for_project` scope** — existing pattern across Tool, Skill, MCPServer, Asset, ConfigItem, Repository. Returns internal + company-scoped + project-scoped resources. Project overrides company by name. Example: `Tool.merged_for_project(project)` returns the union of `scope_type: 'Company', scope_id: project.company_id` and `scope_type: 'Project', scope_id: project.id`
- **Resolution order**: `project (inherit_all) + workflow.base + step` → `.uniq`
- The flag is stored in Workflow's existing `config` jsonb — no migration needed

### Existing Code Context

- `Tool.merged_for_project(project)` — defined in `app/models/tool.rb`, returns company + project tools
- `Skill.merged_for_project(project)` — same pattern in `app/models/skill.rb`
- `MCPServer.merged_for_project(project)` — same pattern in `app/models/mcp_server.rb`
- This flag is designed primarily for board-triggered auto workflows where the user doesn't manually select resources

### File Locations

- Modified: `app/models/workflow.rb` — add `inherit_all_project_resources` helper
- Modified: `app/services/session_config_resolver.rb` — add project resource inclusion logic
- Modified: `test/services/session_config_resolver_test.rb` — add test cases

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb`
- For testing `merged_for_project`, create company-level and project-level tools in factory setup
- Verify deduplication when project tool also appears in step.tool_ids

### References

- [Source: ai/session-config-cascade.md#3.4] — "Workflow: give everything" mode
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.3] — AC and technical notes
- [Source: ai/project-context.md#Multi-tenancy] — `merged_for_project(project)` pattern
- [Source: app/models/tool.rb] — merged_for_project scope

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
