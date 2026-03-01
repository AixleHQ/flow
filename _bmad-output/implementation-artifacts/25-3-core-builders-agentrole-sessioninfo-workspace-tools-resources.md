# Story 25.3: Core Builders (AgentRole, SessionInfo, Workspace, Tools, Resources)

Status: done

## Story

As a system,
I want builders for AgentRole, SessionInfo, Workspace, Tools (shell + MCP + custom), and Resources (repos, assets, skills) that extract content from existing SessionContextService methods,
So that all current context content is generated through composable builders.

## Acceptance Criteria

1. **AgentRole builder with configured agent** — Given a session with a configured agent, when `ContextBuilders::AgentRole` runs, then output includes a section with tag `agent-role`, priority `:important`, position_hint `:top`, containing the agent's system prompt via `agent.to_system_prompt`

2. **AgentRole not applicable without agent** — Given a session without `configured_agent_id`, when `ContextBuilders::AgentRole#applicable?` is called, then it returns `false`

3. **SessionInfo builder** — Given a session with project, agent_type, and mode, when `ContextBuilders::SessionInfo` runs, then output includes a section with tag `session-context`, priority `:info`, containing session ID, agent runtime, mode, and project name

4. **Workspace builder with assets and repos** — Given a session with `input_asset_ids` and `repository_ids`, when `ContextBuilders::Workspace` runs, then output includes a section with tag `workspace`, priority `:important`, describing `/workspace/outputs/`, `/workspace/assets/` (read-only note), and `/workspace/repo/`

5. **Workspace builder without assets** — Given a session without `input_asset_ids`, when Workspace runs, then the assets directory line is not included in output

6. **Tools builder with MCP servers and custom tools** — Given a session with MCP servers, tools, and shell tools, when `ContextBuilders::Tools` runs, then output includes up to 3 sections: `shell-tools` (always), `mcp-servers` (if MCP servers exist), `custom-tools` (if custom tools exist), all with priority `:info`

7. **Tools builder without custom tools** — Given a session without custom tools, when `ContextBuilders::Tools` builds, then no `custom-tools` section is produced (only `shell-tools` and optionally `mcp-servers`)

8. **Resources builder with repos, assets, skills** — Given a session with repositories, input assets, and skills, when `ContextBuilders::Resources` runs, then output includes an `available-resources` section (priority `:info`) containing repositories table, assets list, and skills content

9. **Resources builder with nothing** — Given a session with no repositories, no assets, no skills, when `ContextBuilders::Resources#applicable?` is called, then it returns `false`

10. **Content extraction is 1:1 from SessionContextService** — All content generation logic MUST be extracted from existing `SessionContextService` private methods to ensure behavioral backward compatibility

## Tasks / Subtasks

- [x] Task 1: Create ContextBuilders::AgentRole (AC: #1, #2)
  - [x] Create `app/services/context_builders/agent_role.rb`
  - [x] Override `applicable?` → `session.configured_agent_id.present?`
  - [x] Implement `build` → load agent via `Agent.find_by(id: session.configured_agent_id)`, return section with `agent.to_system_prompt`
  - [x] Tag: `agent-role`, priority: `:important`, position_hint: `:top`
- [x] Task 2: Create ContextBuilders::SessionInfo (AC: #3)
  - [x] Create `app/services/context_builders/session_info.rb`
  - [x] Extract content from `SessionContextService#build_session_context` (lines 301-316)
  - [x] Include: session ID, agent runtime, mode, project name
  - [x] Do NOT include language preference here (moved to CriticalRules in 25.2)
  - [x] Tag: `session-context`, priority: `:info`, position_hint: `:middle`
- [x] Task 3: Create ContextBuilders::Workspace (AC: #4, #5)
  - [x] Create `app/services/context_builders/workspace.rb`
  - [x] Extract content from `SessionContextService#build_workspace_layout` (lines 319-338)
  - [x] Conditionally include `/workspace/assets/` (if input_asset_ids present)
  - [x] Conditionally include `/workspace/repo/` (if repository_ids present)
  - [x] Tag: `workspace`, priority: `:important`, position_hint: `:middle`
- [x] Task 4: Create ContextBuilders::Tools (AC: #6, #7)
  - [x] Create `app/services/context_builders/tools.rb`
  - [x] Produces multiple sections: `shell-tools` (always), `mcp-servers` (conditional), `custom-tools` (conditional)
  - [x] Extract shell tools content from `SessionContextService#build_shell_tools_section` (lines 341-357)
  - [x] Extract MCP descriptions from `SessionContextService#build_mcp_descriptions` (lines 359-372) using `resolve_mcp_servers_for_descriptions` logic
  - [x] Extract tool descriptions from `SessionContextService#build_tool_descriptions` (lines 374-403) including `tool_execution_modes_section`
  - [x] All sections: priority `:info`, position_hint `:bottom`
- [x] Task 5: Create ContextBuilders::Resources (AC: #8, #9)
  - [x] Create `app/services/context_builders/resources.rb`
  - [x] Override `applicable?` → true only if session has repos, assets, or skills
  - [x] Extract repositories content from `SessionContextService#build_repositories_section` (lines 615-639)
  - [x] Extract skills content from `SessionContextService#build_skills_section` (lines 435-449)
  - [x] Include input assets listing (path mapping to `/workspace/assets/`)
  - [x] Tag: `available-resources`, priority `:info`, position_hint `:middle`
- [x] Task 6: Write tests for all 5 builders (AC: #1-#10)
  - [x] Create test files in `test/services/context_builders/`
  - [x] `agent_role_test.rb` — applicable with/without agent, section tag/priority, content includes system prompt
  - [x] `session_info_test.rb` — section content includes session ID, agent type, mode, project
  - [x] `workspace_test.rb` — with/without assets, with/without repos
  - [x] `tools_test.rb` — shell tools always present, MCP conditional, custom tools conditional
  - [x] `resources_test.rb` — applicable? logic, repos table, skills content, assets listing

## Dev Notes

### Architecture Patterns

- **1:1 Content Extraction:** Each builder's content generation MUST match the corresponding `SessionContextService` private method output. This is a refactoring, not a rewrite.
- **Multiple Sections per Builder:** The `Tools` builder returns up to 3 sections (`shell-tools`, `mcp-servers`, `custom-tools`). The `Resources` builder may return sections for repos, assets, and skills. Builders return `Array<ContextSection>`.
- **Conditional Sections:** Builders use `applicable?` for entire builder applicability. Within `build`, individual sections are only added if data exists (e.g., `sections << mcp_section if mcp_servers.any?`).

### Methods to Extract From SessionContextService

| Builder | Source Method | Lines |
|---------|-------------|-------|
| AgentRole | `build_agent_persona` | 289-299 |
| SessionInfo | `build_session_context` | 301-316 |
| Workspace | `build_workspace_layout` | 319-338 |
| Tools (shell) | `build_shell_tools_section` | 341-357 |
| Tools (MCP) | `build_mcp_descriptions` + `resolve_mcp_servers_for_descriptions` | 359-372, 487-511 |
| Tools (custom) | `build_tool_descriptions` + `tool_execution_modes_section` | 374-433 |
| Resources (repos) | `build_repositories_section` | 615-639 |
| Resources (skills) | `build_skills_section` | 435-449 |

### Key Data Access Patterns

- **Agent:** `Agent.find_by(id: session.configured_agent_id)` → `agent.to_system_prompt`
- **MCP Servers:** `MCPServer.where(id: session.mcp_server_ids, enabled: true)` — always include internal `palad-tools`
- **Tools:** `session.available_tools` — includes internal tools auto-injected for workflow sessions
- **Skills:** `Skill.where(id: session.skill_ids)`
- **Repositories:** `Repository.where(id: session.repository_ids)` — check `session.metadata["failed_repos"]` for clone failures
- **Assets:** `session.input_asset_ids` — for workspace layout, not loading actual files

### Anti-Patterns to Avoid

- Do NOT call `SessionContextService` from builders — extract the logic, don't delegate
- Do NOT access `session.session_config` JSONB directly — use normalized accessors like `session.mcp_server_ids`, `session.skill_ids`, `session.repository_ids`, `session.input_asset_ids`
- Do NOT include language preference in SessionInfo — that's now in CriticalRules (Story 25.2)
- Do NOT include non-interactive rules in any of these builders — that's CriticalRules (Story 25.2)

### Testing Standards

- **Framework:** Minitest, mocha for mocks, factory_bot for factories
- **Each builder tested in isolation** — mock session and associations
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/`

### Project Structure Notes

- New files in `app/services/context_builders/`: `agent_role.rb`, `session_info.rb`, `workspace.rb`, `tools.rb`, `resources.rb`
- Test files in `test/services/context_builders/`
- Depends on: Story 25.1 (ContextSection), Story 25.2 (ContextBuilders::Base)
- These builders do NOT modify SessionContextService yet — that happens in Story 25.7

### References

- [Source: app/services/session_context_service.rb] — All methods being extracted
- [Source: ai/session-context-constructor.md#5 Builders Detail Design] — Builder designs
- [Source: ai/epics/epic-25-unified-context-constructor.md#Story 25.3] — Acceptance criteria
- [Source: ai/project-context.md#Tool visibility rules] — Tool injection logic

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- All tasks completed. Implementation follows epic design. 59 total tests across all Epic 25 stories, 212 assertions, 0 failures.

### File List

- `app/services/context_builders/agent_role.rb`
- `app/services/context_builders/session_info.rb`
- `app/services/context_builders/workspace.rb`
- `app/services/context_builders/tools.rb`
- `app/services/context_builders/resources.rb`
- `test/services/context_builders/agent_role_test.rb`
- `test/services/context_builders/session_info_test.rb`
- `test/services/context_builders/workspace_test.rb`
- `test/services/context_builders/tools_test.rb`
- `test/services/context_builders/resources_test.rb`
