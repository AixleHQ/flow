# Story 29.5: Step `required_agent_runtime` Field

Status: done

## Story

As a workflow designer,
I want to mark a step as requiring a specific agent runtime,
So that certain steps always run on the correct agent regardless of user preferences.

## Acceptance Criteria

1. **Step requirement overrides all** — Given a Step with `required_agent_runtime = "claude_code"` and User default credential runtime = "gemini_cli", when resolver resolves agent_runtime, then result is `"claude_code"`

2. **Workflow run override** — Given a Step with `required_agent_runtime = nil` and WorkflowRun with `agent_runtime = "gemini_cli"`, when resolver resolves, then result is `"gemini_cli"`

3. **User default credential** — Given Step `required_agent_runtime = nil`, WorkflowRun `agent_runtime = nil`, User `default_agent_credential.runtime = "claude_code"`, when resolver resolves, then result is `"claude_code"`

4. **Latest credential fallback** — Given no step requirement, no run override, no default credential set, but User has agent_credentials with the most recent having runtime "codex", when resolver resolves, then result is `"codex"`

5. **Hardcoded fallback** — Given no step requirement, no run override, no user credentials at all, when resolver resolves, then result is `"claude_code"`

6. **Standalone unaffected** — Standalone sessions use `session.agent_type` directly, the priority chain does not apply

7. **Migration** — `required_agent_runtime` column added to `steps` table as nullable string

## Tasks / Subtasks

- [ ] Task 1: Create migration (AC: #7)
  - [ ] `add_column :steps, :required_agent_runtime, :string, null: true`
  - [ ] No default value — nil means "no requirement"
- [ ] Task 2: Implement agent_runtime priority chain in resolver (AC: #1-#5)
  - [ ] Priority: `step.required_agent_runtime` → `workflow_run.agent_runtime` → `user.default_agent_credential&.runtime` → `user.agent_credentials.order(created_at: :desc).first&.runtime` → `"claude_code"`
  - [ ] Use `.presence` checks to skip nil/empty values
- [ ] Task 3: Verify standalone pass-through (AC: #6)
  - [ ] Standalone branch returns `session.agent_type` directly
- [ ] Task 4: Update Step serializer (if exists)
  - [ ] Include `required_agent_runtime` in API response
- [ ] Task 5: Write tests (AC: #1-#6)
  - [ ] Test step required overrides everything
  - [ ] Test workflow_run.agent_runtime used when step has none
  - [ ] Test user default credential used when no run override
  - [ ] Test latest credential fallback
  - [ ] Test hardcoded "claude_code" fallback
  - [ ] Test standalone returns session.agent_type

## Dev Notes

### Architecture Patterns

- **Priority chain pattern** — only `agent_runtime` is scalar with priority resolution. All other resources are additive sets
- **User.default_agent_credential** — this association doesn't exist yet. It will be added in Epic 30 (Story 30.1). For THIS story, use fallback: `user.agent_credentials.order(created_at: :desc).first&.runtime`. The `default_agent_credential_id` column on User is NOT part of this epic
- **Workaround**: Until Epic 30 adds `User#default_agent_credential`, the resolver should use `user.agent_credentials.order(created_at: :desc).first` as the "default"
- **agent_type column** — TerminalSession uses `agent_type` (string), WorkflowRun uses `agent_runtime` (string). Both store the same enum values: `claude_code`, `cursor_cli`, `codex`, `gemini_cli`

### Existing Code Context

- `LaunchStepSessionActivity#execute` line: `agent_type = workflow_run.agent_runtime || "claude_code"` — this is the current simplistic resolution, replaced by the priority chain
- `Step` model — currently has no `required_agent_runtime` column
- `WorkflowRun` model — has `agent_runtime` column (string, nullable)
- `User` model — `has_many :agent_credentials`. No `default_agent_credential` yet (Epic 30)
- `AgentCredential` model — has `agent_type` column (the runtime identifier)

### File Locations

- New: `db/migrate/XXXXXXXX_add_required_agent_runtime_to_steps.rb`
- Modified: `app/services/session_config_resolver.rb` — implement full priority chain
- Modified: `test/services/session_config_resolver_test.rb` — agent_runtime tests

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb`
- **Migration:** `docker exec app-web-1 bundle exec rails db:migrate`
- Create agent_credentials via factory to test different runtime values

### References

- [Source: ai/session-config-cascade.md#3.1] — agent_runtime priority chain with code
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.5] — AC and priority chain
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb#11] — Current `workflow_run.agent_runtime || "claude_code"`
- [Source: ai/session-config-cascade.md#6.1] — User default_agent_credential design (Epic 30 scope)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
