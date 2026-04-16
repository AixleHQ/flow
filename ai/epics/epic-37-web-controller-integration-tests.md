# E2: Web Controller Integration Tests — Full Coverage

## Overview

Add integration tests for **every** web controller action that currently lacks test coverage. One test per action, success case only. Uses existing `WebTestCase` pattern with `assert_response :success` + `assert_inertia_component` for GET actions that render Inertia pages, and `assert_response :redirect` / `assert_response :success` for mutation actions.

---

## Existing Pattern

```ruby
require_relative "../../../web_test_case"

class Web::Company::Projects::BoardsControllerTest < WebTestCase
  setup do
    @company, @user = create_authenticated_user
    @project = create(:project, company: @company, owner: @user)
    web_sign_in(@user)
  end

  test "show renders board page" do
    get company_project_board_path(@project)
    assert_response :success
    assert_inertia_component "Projects/Board/BoardPage"
  end
end
```

**Rules:**
- One test per action, success case only
- GET (render) → `assert_response :success` + `assert_inertia_component`
- POST/PATCH/DELETE (mutation) → `assert_response :redirect` or `assert_response :success` (for JSON)
- Use FactoryBot for test data
- Use named route helpers, not hardcoded paths

---

## Controller Inventory: What Needs Tests

### Already Covered (25 tests, no changes needed)

| Controller | Actions Tested |
|------------|----------------|
| Company::ProjectsController | index, create, destroy |
| Company::MembersController | index |
| Company::RepositoriesController | index |
| Company::IntegrationsController | index |
| Company::ConfigItemsController | index |
| Company::AssetsController | index |
| Company::SkillsController | index |
| Company::ToolsController | index |
| Company::AgentsController | index |
| Company::MCPServersController | index |
| Company::SessionsController | index, new, show |
| Company::WorkflowsController | index |
| Projects::OverviewController | index |
| Projects::AnalyticsController | index |
| Projects::SettingsController | show |
| Projects::MembersController | index |
| Projects::RepositoriesController | index |
| Projects::IntegrationsController | index |
| Projects::ConfigItemsController | index |
| Projects::SkillsController | index |
| Projects::ToolsController | index |
| Projects::AgentsController | index |
| Projects::MCPServersController | index |
| Projects::SessionsController | index, new, show |
| Projects::BoardsController | show |

### Missing: Existing test files need extra action coverage

These controllers have a test file but only cover `index`. Add remaining CRUD actions.

| Controller | Existing | Missing Actions |
|------------|----------|-----------------|
| Company::MembersController | index | create, update, destroy |
| Company::RepositoriesController | index | create, update, destroy, branches |
| Company::IntegrationsController | index | github_setup, create, destroy |
| Company::ConfigItemsController | index | create, update, destroy |
| Company::AssetsController | index | create, destroy, versions, download |
| Company::SkillsController | index | create, destroy |
| Company::ToolsController | index | create, update, destroy |
| Company::AgentsController | index | create, update, destroy |
| Company::MCPServersController | index | create, update, destroy |
| Company::WorkflowsController | index | builder, create, show, update, destroy |
| Projects::SettingsController | show | update |
| Projects::MembersController | index | create, destroy |
| Projects::RepositoriesController | index | create, update, destroy |
| Projects::IntegrationsController | index | create, destroy |
| Projects::ConfigItemsController | index | create, update, destroy |
| Projects::SkillsController | index | create, destroy |
| Projects::ToolsController | index | create, update, destroy |
| Projects::AgentsController | index | create, update, destroy |
| Projects::MCPServersController | index | create, update, destroy |
| Projects::BoardsController | show | create, update, destroy |

### Missing: New test files needed

| Controller | Actions | Test File Path |
|------------|---------|----------------|
| **Top-Level** | | |
| Web::PagesController | privacy_policy, terms_of_service | `test/integration/web/pages_controller_test.rb` |
| Web::HomeController | show | `test/integration/web/home_controller_test.rb` |
| Web::ProfileController | show, update, update_default_model, destroy_credential | `test/integration/web/profile_controller_test.rb` |
| Web::OnboardingController | show, update | `test/integration/web/onboarding_controller_test.rb` |
| Web::TerminalSessionsController | show, create, destroy, finish | `test/integration/web/terminal_sessions_controller_test.rb` |
| Web::AgentModelsController | index | `test/integration/web/agent_models_controller_test.rb` |
| **Project-Level** | | |
| Projects::WorkflowsController | index, builder, create, show, update, destroy | `test/integration/web/company/projects/workflows_controller_test.rb` |
| Projects::WorkflowRunsController | index, show, create, cancel, approve_step, retry_step, skip_step | `test/integration/web/company/projects/workflow_runs_controller_test.rb` |
| Projects::WorkflowRunAssetsController | index, export, download, export_all | `test/integration/web/company/projects/workflow_run_assets_controller_test.rb` |
| Projects::AssetsController | index, create, destroy, versions, download | `test/integration/web/company/projects/assets_controller_test.rb` |
| Projects::AixleBuilderController | show, start, session | `test/integration/web/company/projects/aixle_builder_controller_test.rb` |
| **Board Nested** | | |
| Board::ColumnsController | index, show, create, update, destroy, reorder | `test/integration/web/.../board/columns_controller_test.rb` |
| Board::TasksController | index, show, create, update, destroy, move, workflow_runs, trigger_workflow | `test/integration/web/.../board/tasks_controller_test.rb` |
| Board::ViewPresetsController | index, create, destroy | `test/integration/web/.../board/view_presets_controller_test.rb` |
| Board::ActivitiesController | index | `test/integration/web/.../board/activities_controller_test.rb` |
| **Board Task Nested** | | |
| Board::Task::ActivitiesController | index | `test/integration/web/.../board/task/activities_controller_test.rb` |
| Board::Task::StatisticsController | show | `test/integration/web/.../board/task/statistics_controller_test.rb` |
| Board::Task::TransitionsController | index | `test/integration/web/.../board/task/transitions_controller_test.rb` |
| Board::Task::AssetsController | index, create, destroy | `test/integration/web/.../board/task/assets_controller_test.rb` |
| Board::Task::CommentsController | index, create | `test/integration/web/.../board/task/comments_controller_test.rb` |
| Board::Task::WaitsController | destroy | `test/integration/web/.../board/task/waits_controller_test.rb` |
| **Workflow Steps Nested** | | |
| Projects::Workflows::StepsController | index, show, create, update, destroy, reorder | `test/integration/web/.../projects/workflows/steps_controller_test.rb` |
| Company::Workflows::StepsController | index, show, create, update, destroy, reorder | `test/integration/web/company/workflows/steps_controller_test.rb` |
| **Sessions Nested** | | |
| Company::Sessions::ArtifactsController | index, review | `test/integration/web/company/sessions/artifacts_controller_test.rb` |

---

## Stories

### Story 2.1: Extend Existing Tests — Company CRUD Actions

Add missing CRUD action tests to the 10 existing company-level test files. Each file gets additional tests for create, update, destroy (and other actions listed above).

**Estimated scope:** ~35 new tests across 10 files

**Acceptance Criteria:**
- [ ] Each company-level controller action has exactly one success-case test
- [ ] Mutation tests use proper params from existing factories
- [ ] All tests pass in Docker: `docker compose exec web bundle exec rails test test/integration/web/company/`

### Story 2.2: Extend Existing Tests — Project CRUD Actions

Add missing CRUD action tests to the existing project-level test files.

**Estimated scope:** ~30 new tests across 10 files

**Acceptance Criteria:**
- [ ] Each project-level controller action has exactly one success-case test
- [ ] All tests pass: `docker compose exec web bundle exec rails test test/integration/web/company/projects/`

### Story 2.3: New Tests — Top-Level Controllers

Create test files for: PagesController, HomeController, ProfileController, OnboardingController, TerminalSessionsController, AgentModelsController.

**Notes:**
- `PagesController` and `HomeController` don't require auth
- `OnboardingController` needs a user WITHOUT completed onboarding
- `TerminalSessionsController` returns JSON, not Inertia — use `assert_response :success` without `assert_inertia_component`
- `Web::SessionsController` (login/logout) is excluded — it's the auth mechanism itself

**Estimated scope:** ~12 new tests across 6 files

### Story 2.4: New Tests — Board & Task Nested Controllers

Create test files for board/columns, board/tasks, board/view_presets, board/activities, and all board/task/* controllers.

**Setup complexity:** These need a board + column + task hierarchy in `setup`.

**Estimated scope:** ~25 new tests across 11 files

### Story 2.5: New Tests — Workflow, WorkflowRun, and Steps Controllers

Create test files for project workflows, workflow runs, workflow run assets, workflow steps (both company and project scoped), and session artifacts.

**Setup complexity:** Workflows need steps/runs. WorkflowRunAssets need existing run with assets.

**Estimated scope:** ~25 new tests across 6 files

### Story 2.6: New Tests — Aixle Builder Controller

Create test file for AixleBuilderController (show, start, session).

**Notes:**
- `start` creates a TerminalSession via SessionService — needs Temporal stubs
- `session` needs an existing aixle_builder-tagged session

**Estimated scope:** ~3 tests, 1 file

---

## Total Estimated Scope

| Category | New Tests | New Files |
|----------|-----------|-----------|
| Company CRUD | ~35 | 0 (extend existing) |
| Project CRUD | ~30 | 0 (extend existing) |
| Top-Level | ~12 | 6 |
| Board & Task | ~25 | 11 |
| Workflows & Steps | ~25 | 6 |
| Aixle Builder | ~3 | 1 |
| **Total** | **~130** | **24** |

---

## Technical Notes

- **JSON actions** (board/task nested controllers often respond with JSON, not Inertia): use `assert_response :success` + check `response.parsed_body`
- **Temporal stubs**: Any action that triggers `SessionService.create_and_start` needs `TemporalService.stubs(:start_workflow)` or similar
- **File uploads**: Asset create actions need `fixture_file_upload` from UploadSupport
- **Route helpers**: Use `rails routes` output to get correct helper names for nested routes
