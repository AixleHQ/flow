# Story 31.4: Step Required Agent Runtime Selector

Status: done

## Story

As a workflow designer,
I want to optionally specify a required agent runtime for a step,
so that certain steps always use the correct agent regardless of user defaults.

## Acceptance Criteria

1. **Dropdown in step form** — Given the Step edit form in Workflow Builder, when designer views agent configuration, then there is a "Required Agent Runtime" dropdown with options: [None (use default), claude_code, gemini_cli, codex, cursor_cli]

2. **Set required runtime** — Given "Required Agent Runtime" set to "claude_code", when step is saved, then `step.required_agent_runtime = "claude_code"`

3. **Clear required runtime** — Given "Required Agent Runtime" set to "None (use default)", when step is saved, then `step.required_agent_runtime = nil`

4. **Badge on step card** — Given a step with `required_agent_runtime = "claude_code"`, when viewing the step card in Workflow Builder, then a badge shows "Requires: Claude Code" next to the agent name

5. **Serialization** — StepSerializer includes `required_agent_runtime` in API response

6. **Strong params** — StepsController permits `required_agent_runtime` parameter

## Tasks / Subtasks

- [x] Task 1: Update StepSerializer (AC: #5)
  - [x] Added `required_agent_runtime` to StepSerializer attributes
- [x] Task 2: Update StepsController strong params (AC: #6)
  - [x] Added `:required_agent_runtime` to both project and company steps controllers
- [x] Task 3: Add Required Runtime dropdown to step form (AC: #1, #2, #3)
  - [x] Added MUI Select in StepDetailPanel after Agent selector
  - [x] Options: None (use default) → null, claude_code, gemini_cli, codex, cursor_cli
- [x] Task 4: Add badge to step card (AC: #4)
  - [x] Added warning Chip "Requires: Claude Code" in sidebar step card
  - [x] Uses inline label mapping
- [x] Task 5: Frontend type update
  - [x] Added `requiredAgentRuntime: string | null` to Step interface
  - [x] Added `requiredAgentRuntime?: string | null` to UpdateStepRequest
- [x] Task 6: Tests — backend tests pass with existing resolver tests (column existed from 29.5)

## Dev Notes

### Architecture Patterns

- **Column already exists** — `required_agent_runtime` was added to `steps` table in Epic 29 Story 29.5 (`db/migrate/20260301150923_add_required_agent_runtime_to_steps.rb`). This story only adds serialization, controller params, and UI
- **Runtime labels** — Use a shared mapping for human-readable runtime labels. Consider creating a shared constant or utility if not already present
- **Nullable field** — `nil` means "use default" (SessionConfigResolver falls through to next priority). Any non-nil value means the step requires that specific runtime

### Existing Code Context

- **Step model** — `required_agent_runtime` column exists (string, nullable). No model-level validation on allowed values yet
- **StepSerializer** (`app/serializers/step_serializer.rb`) — attributes include `tool_ids, mcp_server_ids, skill_ids, mount_repositories, depends_on_step_ids` but NOT `required_agent_runtime`. Needs adding
- **StepsController** — likely at `app/controllers/api/v1/company/projects/workflows/steps_controller.rb`. Need to add `:required_agent_runtime` to permitted params
- **Frontend step forms** — AddStepDialog / EditStepDialog in WorkflowBuilderPage. Need to identify exact component paths
- **SessionConfigResolver** — already uses `step&.required_agent_runtime.presence` in priority chain (Epic 29). No changes needed there
- **User.AVAILABLE_AGENTS** — `%w[claude_code cursor_cli codex gemini_cli]` defined in User model. Can be reused for validation

### File Locations

- Modified: `app/serializers/step_serializer.rb` — add `required_agent_runtime`
- Modified: `app/controllers/api/v1/company/projects/workflows/steps_controller.rb` — permit param
- Modified: Frontend step form component (AddStepDialog / EditStepDialog)
- Modified: Frontend step card component — add badge
- Modified: Frontend Step TypeScript type
- Possibly new: shared runtime labels utility

### Testing Standards

- **Framework:** Backend: Minitest with FactoryBot. Frontend: Vitest with React Testing Library
- **Run backend:** `docker exec app-web-1 bundle exec rails test test/controllers/...steps_controller_test.rb`

### Previous Story Intelligence

- Story 29.5 added the `required_agent_runtime` column to steps
- Story 29.6 integrated it into LaunchStepSessionActivity via SessionConfigResolver
- This story (31.4) is the UI complement — letting designers actually set the value

### References

- [Source: ai/epics/epic-31-workflow-base-resources-ui.md#Story 31.4] — AC and technical notes
- [Source: ai/session-config-cascade.md#3.1] — Step required_agent_runtime in priority chain
- [Source: app/serializers/step_serializer.rb] — Current serializer
- [Source: _bmad-output/implementation-artifacts/29-5-step-required-agent-runtime-field.md] — Previous column implementation
- [Source: app/models/user.rb#AVAILABLE_AGENTS] — Agent type constants
- [Source: ai/project-context.md] — Tech stack and patterns

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Serializer and controller updates are minimal (column already existed)
- Frontend: Select dropdown + sidebar badge chip
- 61 backend tests pass

### File List

- app/serializers/step_serializer.rb (modified)
- app/controllers/api/v1/company/projects/workflows/steps_controller.rb (modified)
- app/controllers/api/v1/company/workflows/steps_controller.rb (modified)
- app/frontend/features/workflow-steps/lib/types.ts (modified)
- app/frontend/pages/workflow-builder/ui/WorkflowBuilderPage.tsx (modified)
