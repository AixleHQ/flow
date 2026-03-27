# Story 17.6: Update Workflow Initiation

Status: review

## Story

As a platform engineer,
I want `ContainerWorkflowService` to dispatch to the correct workflow (agent vs tool),
so that callers don't need to know workflow implementation details.

## Acceptance Criteria

1. **AC1: Agent session dispatch** — `ContainerWorkflowService.start_session(session_id:)` dispatches to `Workflows::AgentContainerWorkflow` with `{ session_id: }` input. No more `strategy_type` / `strategy_input` construction.

2. **AC2: Tool execution dispatch** — `ContainerWorkflowService.execute_tool(tool_id:, parameters:, project_id:, timeout:)` dispatches to `Workflows::ToolExecutionWorkflow` with direct params.

3. **AC3: Auth setup sessions** — `start_session` handles `auth_setup` type sessions via the same `AgentContainerWorkflow` (strategy resolved from session internally).

4. **AC4: Workflow ID** — Agent workflow ID: `agent-session-{session_id}`. Tool workflow ID: `tool-execution-{tool_id}-{timestamp}`.

5. **AC5: Controller integration** — `TerminalSessionsController#create` calls `ContainerWorkflowService.start_session(session_id:)` without building strategy hashes. Tool controllers call `execute_tool` directly.

6. **AC6: Backward compat removal** — Old methods `start_agent_session_workflow`, `start_auth_setup_workflow` consolidated into `start_session`. Old method signatures removed.

## Tasks / Subtasks

- [x] Task 1: Refactor ContainerWorkflowService (AC: #1, #2, #3, #4, #6)
  - [x] 1.1 Implement `start_session(session_id:)` — loads session, dispatches to AgentContainerWorkflow
  - [x] 1.2 Simplify `execute_tool(...)` — dispatches to ToolExecutionWorkflow
  - [x] 1.3 Remove old methods and strategy hash construction
  - [x] 1.4 Update workflow ID patterns
- [x] Task 2: Update TerminalSessionsController (AC: #5)
  - [x] 2.1 Simplify create action — call start_session(session_id:) only
  - [x] 2.2 Remove strategy_type/strategy_input construction from controller
- [x] Task 3: Update tool execution entry points (AC: #5)
  - [x] 3.1 Review InternalToolsService and update workflow dispatch
- [x] Task 4: Write tests
  - [x] 4.1 Test ContainerWorkflowService.start_session for auth_setup and agent_session
  - [x] 4.2 Test ContainerWorkflowService.execute_tool
  - [x] 4.3 Test controller integration

## Dev Notes

### Current flow (complex)

```
Controller → builds {strategy_type: "agent_session", strategy_input: {user_id, agent_type, session_id, route_token, credential_id, mode}}
           → ContainerWorkflowService.start_agent_session_workflow(strategy_type:, strategy_input:)
           → UnifiedContainerWorkflow(strategy_type:, strategy_input:)
```

### New flow (simple)

```
Controller → ContainerWorkflowService.start_session(session_id:)
           → AgentContainerWorkflow(session_id:)
```

### Key files to modify

- `web/app/services/container_workflow_service.rb` — major refactor (~50 lines removed)
- `web/app/controllers/api/v1/terminal_sessions_controller.rb` — simplify create
- `web/app/controllers/api/v1/company/terminal_sessions/artifacts_controller.rb` — if uses workflow service

### Controller simplification

Current in `terminal_sessions_controller.rb`:
```ruby
strategy_type = session.session_type == "auth_setup" ? "agent_auth" : "agent_session"
strategy_input = { user_id: current_user.id, agent_type: session.agent_type, session_id: session.id, route_token: session.route_token, credential_id: credential&.id, mode: session.mode }
ContainerWorkflowService.start_agent_session_workflow(strategy_type: strategy_type, strategy_input: strategy_input)
```

Becomes:
```ruby
ContainerWorkflowService.start_session(session_id: session.id)
```

### Dependencies

- Requires 17.2 (AgentContainerWorkflow) and 17.3 (ToolExecutionWorkflow) to be created
- Should be implemented after 17.2 and 17.3

### References

- [Source: web/app/services/container_workflow_service.rb](web/app/services/container_workflow_service.rb)
- [Source: web/app/controllers/api/v1/terminal_sessions_controller.rb](web/app/controllers/api/v1/terminal_sessions_controller.rb)
