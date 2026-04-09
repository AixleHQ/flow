# Story 36.3: Add before_action :dynamic_authorize! to Project Controllers

Status: review

## Story

As a developer,
I want `before_action :dynamic_authorize!` wired into all project-scoped controllers,
so that every project-level endpoint is authorized via Pundit policies with `project_accessible?` checks.

## Background — What Story 36-1 Already Did

Story 36-1 created the full authorization foundation. The following is already in place:

1. **`Web::Company::Projects::ApplicationController`** already has the skip-then-re-add pattern:
   ```ruby
   skip_before_action :dynamic_authorize!
   before_action :set_project
   before_action :dynamic_authorize!
   ```
   This ensures `@project` is loaded before `dynamic_authorize!` runs, and `policy_context` returns `ProjectContext.new(current_user, params, project: @project)`.

2. **`ProjectContext`** exists at `app/contexts/project_context.rb` — wraps `user`, `params`, and `project`.

3. **All project-level policies** exist under `app/policies/web/company/projects/` including nested `board/`, `board/task/`, and `workflows/`. They all use the `project_accessible?` pattern: `context.project&.accessible_by?(current_user)`.

4. **`AuthorizationConcern`** resolves policy from controller namespace:
   - `Web::Company::Projects::AgentsController` → `authorize([:web, :company, :projects, :agents])` → `Web::Company::Projects::AgentsPolicy`
   - `Web::Company::Projects::Board::TasksController` → `authorize([:web, :company, :projects, :board, :tasks])` → `Web::Company::Projects::Board::TasksPolicy`

**Since `before_action :dynamic_authorize!` is already on the project base controller and all policies exist, this story is about verifying it works end-to-end across all 30+ project controllers and fixing any issues.**

## Acceptance Criteria

1. All project-scoped controllers authorize via `dynamic_authorize!` inherited from `Projects::ApplicationController`
2. Users with project access can reach all project controller actions
3. Users WITHOUT project access are rejected with "not authorized" flash
4. Board and board/task nested controllers authorize correctly through their inheritance chain
5. Workflow steps nested controller authorizes correctly
6. No `Pundit::AuthorizationNotPerformedError` on any project-scoped route
7. All existing tests pass: `docker compose exec web bundle exec rails test`

## Tasks / Subtasks

- [x] Task 1: Audit policy action coverage against controller actions (AC: 1, 6)
  - [x] Verify each project controller's public actions have a matching policy method
  - [x] Check the full "Policy/Controller Action Matrix" below for mismatches
  - [x] Add any missing policy action methods

- [x] Task 2: Verify inheritance chain for nested controllers (AC: 4, 5)
  - [x] `Board::ApplicationController` inherits from `Projects::ApplicationController` (indirectly via `Board::ApplicationController < Projects::ApplicationController` or similar)
  - [x] `Board::Task::ApplicationController` inherits from `Board::ApplicationController`
  - [x] `Workflows::ApplicationController` inherits from `Projects::ApplicationController`
  - [x] Confirm all inherit `dynamic_authorize!` and `policy_context` returns `ProjectContext`

- [x] Task 3: Verify `set_project` runs BEFORE `dynamic_authorize!` (AC: 1)
  - [x] The skip-then-re-add pattern in `Projects::ApplicationController` guarantees this
  - [x] Confirm no child controller overrides or skips `set_project`

- [x] Task 4: Run full test suite (AC: 7)
  - [x] `docker compose exec web bundle exec rails test`
  - [x] Fix any authorization-related failures

- [x] Task 5: Fix any authorization failures discovered (AC: 6, 7)
  - [x] Resolve any `Pundit::AuthorizationNotPerformedError` for missing policy methods
  - [x] Resolve any `Pundit::NotAuthorizedError` that shouldn't occur

## Dev Notes

### How Project-Level Authorization Works

1. Request hits `Projects::ApplicationController`
2. `skip_before_action :dynamic_authorize!` cancels the parent's filter
3. `before_action :set_project` loads `@project = Project.for_user(current_user).find(params[:project_id])`
4. `before_action :dynamic_authorize!` re-adds the filter — now runs AFTER `@project` is set
5. `dynamic_authorize!` calls `authorize([:web, :company, :projects, :agents])` (for `AgentsController`)
6. Pundit resolves to `Web::Company::Projects::AgentsPolicy`
7. `pundit_user` returns `ProjectContext.new(current_user, params, project: @project)`
8. Policy checks `context.project&.accessible_by?(current_user)`

### Policy/Controller Action Matrix — Project Level

**Direct project controllers (inherit from `Projects::ApplicationController`):**

| Controller | Actions | Policy | Policy Actions |
|---|---|---|---|
| `AgentsController` | index, create, update, destroy | `projects/agents_policy.rb` | index?, create?, update?, destroy? |
| `AixleBuilderController` | show, start, session | `projects/aixle_builder_policy.rb` | show?, start?, session? |
| `AnalyticsController` | index | `projects/analytics_policy.rb` | index? |
| `AssetsController` | index, create, destroy, versions, download | `projects/assets_policy.rb` | index?, create?, destroy?, versions?, download? |
| `BoardsController` | show, create, update, destroy | `projects/boards_policy.rb` | show?, create?, update?, destroy? |
| `ConfigItemsController` | index, create, update, destroy | `projects/config_items_policy.rb` | index?, create?, update?, destroy? |
| `IntegrationsController` | index, create, destroy | `projects/integrations_policy.rb` | index?, create?, destroy? |
| `MCPServersController` | index, create, update, destroy | `projects/mcp_servers_policy.rb` | index?, create?, update?, destroy? |
| `MembersController` | index, create, destroy | `projects/members_policy.rb` | index?, create?, destroy? |
| `OverviewController` | index | `projects/overview_policy.rb` | index? |
| `RepositoriesController` | index, create, update, destroy | `projects/repositories_policy.rb` | index?, create?, update?, destroy? |
| `SessionsController` | index, new, show | `projects/sessions_policy.rb` | index?, new?, show? |
| `SettingsController` | show, update | `projects/settings_policy.rb` | show?, update? |
| `SkillsController` | index, create, destroy | `projects/skills_policy.rb` | index?, create?, destroy? |
| `ToolsController` | index, create, update, destroy | `projects/tools_policy.rb` | index?, create?, update?, destroy? |
| `WorkflowRunAssetsController` | index, export, download, export_all | `projects/workflow_run_assets_policy.rb` | index?, export?, download?, export_all? |
| `WorkflowRunsController` | index, show, create, cancel, approve_step, retry_step, skip_step | `projects/workflow_runs_policy.rb` | index?, show?, create?, cancel?, approve_step?, retry_step?, skip_step? |
| `WorkflowsController` | index, builder, create, show, update, destroy | `projects/workflows_policy.rb` | index?, builder?, create?, show?, update?, destroy? |

**Board nested controllers (inherit from `Board::ApplicationController`):**

| Controller | Actions | Policy | Policy Actions |
|---|---|---|---|
| `Board::ActivitiesController` | index | `projects/board/activities_policy.rb` | index? |
| `Board::ColumnsController` | index, show, create, update, destroy, reorder | `projects/board/columns_policy.rb` | index?, show?, create?, update?, destroy?, reorder? |
| `Board::TasksController` | index, show, create, update, destroy, move, workflow_runs, trigger_workflow | `projects/board/tasks_policy.rb` | index?, show?, create?, update?, destroy?, move?, workflow_runs?, trigger_workflow? |
| `Board::ViewPresetsController` | index, create, destroy | `projects/board/view_presets_policy.rb` | index?, create?, destroy? |

**Board task nested controllers (inherit from `Board::Task::ApplicationController`):**

| Controller | Actions | Policy | Policy Actions |
|---|---|---|---|
| `Board::Task::ActivitiesController` | index | `board/task/activities_policy.rb` | index? |
| `Board::Task::AssetsController` | index, create, destroy | `board/task/assets_policy.rb` | index?, create?, destroy? |
| `Board::Task::CommentsController` | index, create | `board/task/comments_policy.rb` | index?, create? |
| `Board::Task::StatisticsController` | show | `board/task/statistics_policy.rb` | show? |
| `Board::Task::TransitionsController` | index | `board/task/transitions_policy.rb` | index? |
| `Board::Task::WaitsController` | destroy | `board/task/waits_policy.rb` | destroy? |

**Workflow steps nested controller:**

| Controller | Actions | Policy | Policy Actions |
|---|---|---|---|
| `Workflows::StepsController` | index, show, create, update, destroy, reorder | `projects/workflows/steps_policy.rb` | index?, show?, create?, update?, destroy?, reorder? |

### Inheritance Chain — Confirm These

```
Web::Company::ApplicationController
  └── before_action :require_auth, :dynamic_authorize!
  └── policy_context → BaseContext

  Web::Company::Projects::ApplicationController
    └── skip_before_action :dynamic_authorize!
    └── before_action :set_project, :dynamic_authorize!
    └── policy_context → ProjectContext (overrides parent)

    Web::Company::Projects::Board::ApplicationController
      └── (helper: current_board)
      └── Inherits dynamic_authorize! + ProjectContext

      Web::Company::Projects::Board::Task::ApplicationController
        └── (helper: current_task)
        └── Inherits dynamic_authorize! + ProjectContext

    Web::Company::Projects::Workflows::ApplicationController
      └── (helper: current_workflow, step_params)
      └── Inherits dynamic_authorize! + ProjectContext
```

### Project Scoping — `Project.for_user`

`set_project` uses `Project.for_user(current_user).find(params[:project_id])`. If the user doesn't have access to the project, this raises `ActiveRecord::RecordNotFound` BEFORE authorization even runs. This is fine — it's a double gate (scoping + policy).

### Files to Inspect/Potentially Modify

| File | Expected Change |
|------|----------------|
| `app/policies/web/company/projects/**/*.rb` | Add missing policy actions if any don't match controller |
| `app/controllers/web/company/projects/**/*.rb` | Verify inheritance chain, no changes expected |
| No new files should be created | |

### References

- [Source: app/controllers/web/company/projects/application_controller.rb] — project base with skip/re-add pattern
- [Source: app/controllers/web/company/projects/board/application_controller.rb] — board base
- [Source: app/controllers/web/company/projects/board/task/application_controller.rb] — task base
- [Source: app/policies/web/company/projects/] — all project-level policies
- [Source: app/contexts/project_context.rb] — ProjectContext
- [Source: ai/implementation-artifacts/epic-36-policies-dynamic-authorize.md] — epic design
- [Source: ai/implementation-artifacts/36-1-add-policies-and-contexts-for-web-controllers.md] — story 36-1
- [Source: ai/implementation-artifacts/36-2-company-controllers-before-action.md] — story 36-2

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Debug Log References

### Completion Notes List

- Exhaustive audit of all 29 project-level controllers against their Pundit policies confirmed 100% action coverage — every public controller action has a matching `action?` method in the policy, with zero mismatches in either direction
- Inheritance chain verified for all nested base controllers:
  - `Board::ApplicationController < Projects::ApplicationController` — confirmed
  - `Board::Task::ApplicationController < Board::ApplicationController` — confirmed
  - `Workflows::ApplicationController < Projects::ApplicationController` — confirmed
  - All inherit `dynamic_authorize!` and `policy_context` → `ProjectContext`
- `Projects::ApplicationController` uses the skip-then-re-add pattern: `skip_before_action :dynamic_authorize!` → `before_action :set_project` → `before_action :dynamic_authorize!` — this ensures `@project` is loaded and `policy_context` returns `ProjectContext` before authorization runs
- No child controller overrides or skips `set_project` or `dynamic_authorize!`
- All project-scoped policies use the `project_accessible?` pattern: `context.project&.accessible_by?(current_user)`
- Full test suite: 0 authorization-related failures. All pre-existing failures are in unrelated areas
- No code changes were required — story 36-1 already established all policies and wired the before_action chain

### File List

No files created or modified — verification-only story. Story 36-1 already completed all code changes.
