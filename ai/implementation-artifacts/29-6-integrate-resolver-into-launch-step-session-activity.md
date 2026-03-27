# Story 29.6: Integrate Resolver into LaunchStepSessionActivity

Status: done

## Story

As a system,
I want `LaunchStepSessionActivity` to use `SessionConfigResolver` for determining session configuration,
So that the centralized resolver replaces ad-hoc config assembly in the workflow execution path.

## Acceptance Criteria

1. **Resolver used for agent_runtime** — Given a workflow step being launched, when `LaunchStepSessionActivity` creates the TerminalSession, then `agent_type` is set from `SessionConfigResolver.resolve(session)[:agent_runtime]` instead of `workflow_run.agent_runtime || "claude_code"`

2. **Resolver used for resource attachment** — Given a workflow step session, when resources are attached, then tool_ids, skill_ids, mcp_server_ids, repository_ids, input_asset_ids all come from the resolver's additive resolution (including workflow base resources)

3. **Backward compatibility** — Given existing workflow runs with step-only resources, when resolver is used, then behavior is identical (step resources still attached, just via resolver path)

4. **Two-phase approach** — Session is first created with minimal config, then resolver is called, then resources are attached based on resolver output. This is because resolver needs the session object to navigate associations

5. **All existing tests pass** — No behavioral regression in workflow execution

## Tasks / Subtasks

- [ ] Task 1: Refactor LaunchStepSessionActivity (AC: #1, #2, #4)
  - [ ] Create TerminalSession with basic fields (user, project, session_type, mode)
  - [ ] Set `step_run.terminal_session = session` so resolver can navigate
  - [ ] Call `SessionConfigResolver.resolve(session)` to get resolved config
  - [ ] Set `session.agent_type` from `config[:agent_runtime]`
  - [ ] Replace `attach_resources!` with resolver-based attachment
- [ ] Task 2: Implement resolver-based resource attachment (AC: #2)
  - [ ] `session.tools = Tool.where(id: config[:tool_ids])` if tool_ids present
  - [ ] `session.skills = Skill.where(id: config[:skill_ids])` if skill_ids present
  - [ ] `session.mcp_servers = MCPServer.where(id: config[:mcp_server_ids])` if present
  - [ ] `session.repositories = Repository.where(id: config[:repository_ids])` if present
  - [ ] `session.input_assets = Asset.where(id: config[:input_asset_ids])` if present
- [ ] Task 3: Remove old `attach_resources!` method (AC: #1)
  - [ ] Delete the method after replacement is verified
- [ ] Task 4: Handle mode resolution (AC: #1)
  - [ ] Use `config[:mode]` from resolver instead of inline `resolve_mode`
  - [ ] Remove or simplify `resolve_mode` private method
- [ ] Task 5: Test backward compatibility (AC: #3, #5)
  - [ ] Run full workflow test suite
  - [ ] Verify step-only resources still work (resolver returns step tools when no workflow base)
  - [ ] Verify repository mount logic works through resolver

## Dev Notes

### Architecture Patterns

- **Two-phase creation** — The resolver needs a session with `step_run` association to navigate. So the flow is: (1) create session + link step_run, (2) resolve config, (3) set agent_type + attach resources. This is a slight reorder from current flow
- **Current flow in LaunchStepSessionActivity:**
  1. Read step_run, workflow_run, step
  2. Determine agent_type = `workflow_run.agent_runtime || "claude_code"`
  3. Determine mode via `resolve_mode`
  4. Create TerminalSession with agent_type, mode, etc.
  5. Call `attach_resources!(session, step, workflow_run)` — reads from step only
  6. Link step_run to session
- **New flow:**
  1. Read step_run, workflow_run, step
  2. Create TerminalSession with minimal fields (no agent_type yet)
  3. Link step_run to session
  4. `config = SessionConfigResolver.resolve(session)`
  5. Set `session.update!(agent_type: config[:agent_runtime])`
  6. Attach resources from config

### Existing Code Context

- `LaunchStepSessionActivity` (app/temporal/activities/workflow/launch_step_session_activity.rb) — 84 lines, has `execute`, `resolve_mode`, `attach_resources!`
- `attach_resources!` reads from `step.tool_ids`, `step.skill_ids`, `step.mcp_server_ids`, `step.mount_repositories`, `workflow_run.input_asset_ids` — all of this is now handled by resolver
- `resolve_mode` uses `workflow_run.step_auto_run?`, `workflow_run.mode`, `step.allow_non_interactive` — resolver's `resolve_mode` should handle the same logic

### Critical: Mode Resolution Alignment

The current `resolve_mode` in LaunchStepSessionActivity has `step_auto_run?` logic from `workflow_run.step_overrides`. The resolver's `resolve_mode` (from 29.1) must handle this same logic. If not already included, extend the resolver to support `step_auto_run?` overrides:

```ruby
def resolve_mode
  return session.mode unless workflow_session?
  auto = workflow_run.step_auto_run?(step.id)
  return "non_interactive" if auto == true
  return "non_interactive" if workflow_run.mode.non_interactive?
  return "non_interactive" if workflow_run.mode.mixed? && step.allow_non_interactive && auto != false
  "interactive"
end
```

### File Locations

- Modified: `app/temporal/activities/workflow/launch_step_session_activity.rb` — major refactor
- Possibly modified: `app/services/session_config_resolver.rb` — if mode resolution needs `step_auto_run?`
- Modified tests: `test/temporal/activities/workflow/launch_step_session_activity_test.rb` (if exists)

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/temporal/`
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb`
- Test that workflow sessions now get workflow base tools (new behavior via resolver)
- Test that existing step-only configurations still work

### References

- [Source: ai/session-config-cascade.md#6.3] — LaunchStepSessionActivity integration
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.6] — AC and technical notes
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb] — Current implementation
- [Source: app/services/session_config_resolver.rb] — Resolver (built in 29.1-29.5)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
