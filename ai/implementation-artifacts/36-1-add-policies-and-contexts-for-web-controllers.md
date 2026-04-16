# Story 36.1: Add Policies and Contexts for Web Controllers

Status: review

## Story

As a developer,
I want Pundit policies and contexts mirroring the web controller namespace (same pattern as `Api::V1::Company::*` on `develop`),
so that `dynamic_authorize!` works for all web controllers without changing the existing `AuthorizationConcern`.

## Background — How It Worked on `develop`

The `develop` branch had a working pattern:

1. **`AuthorizationConcern`** — `init_authorize` dynamically defines a method `authorize_<policy_name>` that calls `authorize([:web, :company, :agents])`. Pundit resolves `[:web, :company, :agents]` to `Web::Company::AgentsPolicy` (array-of-symbols → namespaced policy lookup). **This concern does NOT need any code changes.**

2. **`BaseContext`** / **`ProjectContext`** — `pundit_user` returns the context. Company-level controllers use `BaseContext.new(current_user, params)`. Project-level controllers override `policy_context` to return `ProjectContext.new(current_user, params, project: current_project)`.

3. **Namespaced policies** — `Api::V1::Company::ApplicationPolicy` as base, then `Api::V1::Company::AgentsPolicy`, etc. Project-scoped policies inherit from the company base and use `context.project` for access checks.

4. **`before_action :dynamic_authorize!`** — set on `Api::V1::Company::ApplicationController`, skipped where needed.

**Our job:** replicate this exact pattern for `Web::Company::*` controllers.

## Acceptance Criteria

1. `AuthorizationConcern` is NOT modified — the existing code stays as-is
2. `ProjectContext` class is created at `app/contexts/project_context.rb` (inherits `BaseContext`, adds `project` attribute)
3. `Web::Company::Projects::ApplicationController` overrides `policy_context` to return `ProjectContext`
4. `Web::Company::ApplicationPolicy` base policy is created with `current_user` convenience method
5. Company-level policies are created for all controllers under `web/company/`: agents, assets, config_items, integrations, mcp_servers, members, projects, repositories, sessions, skills, tools, workflows
6. Project-level policies are created for all controllers under `web/company/projects/`: agents, aixle_builder, analytics, assets, boards, config_items, integrations, mcp_servers, members, overview, repositories, sessions, settings, skills, tools, workflow_run_assets, workflow_runs, workflows
7. Nested project-level policies are created: board/activities, board/columns, board/tasks, board/view_presets, board/task/activities, board/task/assets, board/task/comments, board/task/statistics, board/task/transitions, board/task/waits, workflows/steps
8. Company-level policies: `current_user.admin?` for all actions (matching `develop` pattern)
9. Project-level policies: `project_accessible?` check using `context.project&.accessible_by?(current_user)` (matching `develop` pattern)
10. `before_action :dynamic_authorize!` is added to `Web::Company::ApplicationController`
11. `MembersController` explicit `authorize` calls are removed (replaced by `dynamic_authorize!`)
12. `Web::Company::IntegrationsController` skips `dynamic_authorize!` for `github_setup` action (if it exists, matching `develop`)
13. All existing tests pass: `docker compose exec web bundle exec rails test`

## Tasks / Subtasks

- [x] Task 1: Create `ProjectContext` (AC: 2)
  - [x] Create `app/contexts/project_context.rb` — inherits `BaseContext`, adds `attr_reader :project`, accepts `project:` keyword

- [x] Task 2: Override `policy_context` in project base controller (AC: 3)
  - [x] In `app/controllers/web/company/projects/application_controller.rb`, override `policy_context` to return `ProjectContext.new(current_user, params, project: @project)`

- [x] Task 3: Create company-level base policy (AC: 4)
  - [x] Create `app/policies/web/company/application_policy.rb` — inherits `::ApplicationPolicy`, adds `current_user` method

- [x] Task 4: Create company-level policies (AC: 5, 8)
  - [x] Create policy files under `app/policies/web/company/` for each controller
  - [x] Policy logic matches `develop` branch API policies (not blanket admin? — nuanced per controller)
  - [x] Actions to define per policy: match the public actions of each controller (index?, show?, create?, update?, destroy?, plus any custom actions)

- [x] Task 5: Create project-level policies (AC: 6, 7, 9)
  - [x] Create policy files under `app/policies/web/company/projects/` for each controller
  - [x] All inherit from `Web::Company::ApplicationPolicy`
  - [x] All use the `project_accessible?` pattern: `context.project&.accessible_by?(current_user)`
  - [x] Include nested policies: `board/*`, `board/task/*`, `workflows/steps`
  - [x] Boards and columns use `project_admin?` for mutations (matching `develop`)
  - [x] Integrations and repositories at project level combine `project_accessible? && admin?` for mutations

- [x] Task 6: Wire up `dynamic_authorize!` (AC: 10, 11, 12)
  - [x] Add `before_action :dynamic_authorize!` to `Web::Company::ApplicationController`
  - [x] Remove explicit `authorize` calls from `MembersController` (dynamic_authorize handles it now)
  - [x] Add `skip_before_action :dynamic_authorize!` where needed (e.g. integrations github_setup)
  - [x] Reorder callbacks in projects controller: `skip + set_project + dynamic_authorize!` to ensure project is loaded before authorization

- [x] Task 7: Run tests (AC: 13)
  - [x] `docker compose exec web bundle exec rails test` — all web integration tests pass (31/31), pre-existing failures in unrelated areas only

## Dev Notes

### AuthorizationConcern — DO NOT MODIFY

The existing concern at `app/controllers/concerns/authorization_concern.rb` works correctly:

- `policy_method_params` for `Web::Company::AgentsController` returns `[:web, :company, :agents]`
- Pundit's `authorize([:web, :company, :agents])` resolves to `Web::Company::AgentsPolicy`
- `policy_method_params` for `Web::Company::Projects::ToolsController` returns `[:web, :company, :projects, :tools]`
- Pundit resolves to `Web::Company::Projects::ToolsPolicy`

This is the same mechanism that worked for `Api::V1::Company::*` on `develop`. The only thing missing is the policy classes themselves.

### ProjectContext — New File

```ruby
# app/contexts/project_context.rb
class ProjectContext < BaseContext
  attr_reader :project

  def initialize(user, params, project:)
    super(user, params)
    @project = project
  end
end
```

This existed on `develop` — exact same code.

### Policy Namespace Structure

```
app/policies/
├── application_policy.rb          # existing — base with context/record/user
├── company_policy.rb              # existing — keep, used by MembersController via MemberPolicy
├── member_policy.rb               # existing — keep for now but MembersController will use Web::Company::MembersPolicy via dynamic_authorize!
├── project_policy.rb              # existing — keep
└── web/
    └── company/
        ├── application_policy.rb  # NEW — base for all web company policies
        ├── agents_policy.rb       # NEW
        ├── assets_policy.rb       # NEW
        ├── config_items_policy.rb # NEW
        ├── integrations_policy.rb # NEW
        ├── mcp_servers_policy.rb  # NEW
        ├── members_policy.rb      # NEW (replaces explicit authorize calls)
        ├── projects_policy.rb     # NEW
        ├── repositories_policy.rb # NEW
        ├── sessions_policy.rb     # NEW
        ├── skills_policy.rb       # NEW
        ├── tools_policy.rb        # NEW
        ├── workflows_policy.rb    # NEW
        └── projects/
            ├── agents_policy.rb
            ├── aixle_builder_policy.rb
            ├── analytics_policy.rb
            ├── assets_policy.rb
            ├── boards_policy.rb
            ├── config_items_policy.rb
            ├── integrations_policy.rb
            ├── mcp_servers_policy.rb
            ├── members_policy.rb
            ├── overview_policy.rb
            ├── repositories_policy.rb
            ├── sessions_policy.rb
            ├── settings_policy.rb
            ├── skills_policy.rb
            ├── tools_policy.rb
            ├── workflow_run_assets_policy.rb
            ├── workflow_runs_policy.rb
            ├── workflows_policy.rb
            ├── board/
            │   ├── activities_policy.rb
            │   ├── columns_policy.rb
            │   ├── tasks_policy.rb
            │   ├── view_presets_policy.rb
            │   └── task/
            │       ├── activities_policy.rb
            │       ├── assets_policy.rb
            │       ├── comments_policy.rb
            │       ├── statistics_policy.rb
            │       ├── transitions_policy.rb
            │       └── waits_policy.rb
            └── workflows/
                └── steps_policy.rb
```

### Company-Level Policy Template (admin-only, from `develop`)

```ruby
# frozen_string_literal: true

module Web
  module Company
    class AgentsPolicy < ApplicationPolicy
      def index?
        current_user.admin?
      end

      def create?
        current_user.admin?
      end

      def update?
        current_user.admin?
      end

      def destroy?
        current_user.admin?
      end
    end
  end
end
```

### Project-Level Policy Template (project access check, from `develop`)

```ruby
# frozen_string_literal: true

module Web
  module Company
    module Projects
      class AgentsPolicy < Web::Company::ApplicationPolicy
        def index?
          project_accessible?
        end

        def create?
          project_accessible?
        end

        def update?
          project_accessible?
        end

        def destroy?
          project_accessible?
        end

        private

        def project
          context.project
        end

        def project_accessible?
          return false unless project

          project.accessible_by?(current_user)
        end
      end
    end
  end
end
```

### MembersController Changes

Current `MembersController` uses explicit `authorize current_company, :index?, policy_class: MemberPolicy` calls. After adding `dynamic_authorize!` to the base, Pundit will auto-resolve `Web::Company::MembersPolicy` from `[:web, :company, :members]`. The explicit calls should be removed to avoid double-authorization.

The new `Web::Company::MembersPolicy` should have admin-only for `create?`, `update?`, `destroy?` and member-accessible `index?` (matching current `MemberPolicy` semantics).

### Controller Changes Summary

| File | Change |
|------|--------|
| `app/controllers/web/company/application_controller.rb` | Add `before_action :dynamic_authorize!` |
| `app/controllers/web/company/projects/application_controller.rb` | Override `policy_context` → `ProjectContext` |
| `app/controllers/web/company/members_controller.rb` | Remove explicit `authorize` calls |
| `app/controllers/web/company/integrations_controller.rb` | Add `skip_before_action :dynamic_authorize!, only: :github_setup` if that action exists |

### Action-to-Policy Mapping — Check Controller Public Methods

For each controller, define policy action methods matching its public actions. Example:
- Controller has `index`, `create`, `update`, `destroy` → policy has `index?`, `create?`, `update?`, `destroy?`
- Controller has `show`, `start` → policy has `show?`, `start?`

Read each controller to list its public actions before creating the policy.

### References

- [Source: develop branch — `app/policies/api/v1/company/`] — full set of API policies
- [Source: develop branch — `app/contexts/project_context.rb`] — ProjectContext
- [Source: develop branch — `app/controllers/api/v1/company/application_controller.rb`] — `before_action :dynamic_authorize!`
- [Source: develop branch — `app/controllers/api/v1/company/projects/application_controller.rb`] — `policy_context` override
- [Source: app/controllers/concerns/authorization_concern.rb] — existing concern (do NOT modify)
- [Source: ai/implementation-artifacts/epic-36-policies-dynamic-authorize.md]

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Debug Log References

- MCPServersPolicy needed uppercase `MCP` class name due to `inflect.acronym "MCP"` in `config/initializers/inflections.rb` — Pundit resolves `[:web, :company, :mcp_servers]` → `Web::Company::MCPServersPolicy` (not `McpServersPolicy`)
- Projects controller needed callback reordering: `set_project` must run before `dynamic_authorize!` so `ProjectContext` has `@project` available. Solved via `skip_before_action :dynamic_authorize!` + re-declare after `set_project`.
- Policy logic copied from `develop` branch API policies — not blanket `admin?` but nuanced: `ProjectsPolicy` allows all authenticated for index/create, `SessionsPolicy` allows all, `RepositoriesPolicy` allows index for all, `BoardsPolicy`/`ColumnsPolicy` use `project_admin?` for mutations, project-level integrations/repos combine `accessible? && admin?`.

### Completion Notes List

- Task 1: `ProjectContext` already existed at `app/contexts/project_context.rb` — verified code matches spec
- Task 2: Added `policy_context` override returning `ProjectContext.new(current_user, params, project: @project)`
- Task 3: Created `Web::Company::ApplicationPolicy` inheriting `::ApplicationPolicy` with private `current_user` method
- Task 4: Created 14 company-level policies (12 direct + 2 nested: sessions/artifacts, workflows/steps) with logic matching `develop` API policies
- Task 5: Created 29 project-level policies including nested board/*, board/task/*, workflows/steps with `project_accessible?` and `project_admin?` patterns matching develop
- Task 6: Added `before_action :dynamic_authorize!`, removed 4 explicit authorize calls from MembersController, added skip for integrations github_setup, reordered callbacks in projects controller
- Task 7: All 31 web integration tests pass. Full suite has 12 failures + 11 errors — all pre-existing in unrelated areas (model validations, adapter tests, service tests)
- Updated 25 existing integration test files to use `role: :admin` since policies now enforce authorization

### File List

New files:
- app/policies/web/company/application_policy.rb
- app/policies/web/company/agents_policy.rb
- app/policies/web/company/assets_policy.rb
- app/policies/web/company/config_items_policy.rb
- app/policies/web/company/integrations_policy.rb
- app/policies/web/company/mcp_servers_policy.rb
- app/policies/web/company/members_policy.rb
- app/policies/web/company/projects_policy.rb
- app/policies/web/company/repositories_policy.rb
- app/policies/web/company/sessions_policy.rb
- app/policies/web/company/skills_policy.rb
- app/policies/web/company/tools_policy.rb
- app/policies/web/company/workflows_policy.rb
- app/policies/web/company/sessions/artifacts_policy.rb
- app/policies/web/company/workflows/steps_policy.rb
- app/policies/web/company/projects/agents_policy.rb
- app/policies/web/company/projects/aixle_builder_policy.rb
- app/policies/web/company/projects/analytics_policy.rb
- app/policies/web/company/projects/assets_policy.rb
- app/policies/web/company/projects/boards_policy.rb
- app/policies/web/company/projects/config_items_policy.rb
- app/policies/web/company/projects/integrations_policy.rb
- app/policies/web/company/projects/mcp_servers_policy.rb
- app/policies/web/company/projects/members_policy.rb
- app/policies/web/company/projects/overview_policy.rb
- app/policies/web/company/projects/repositories_policy.rb
- app/policies/web/company/projects/sessions_policy.rb
- app/policies/web/company/projects/settings_policy.rb
- app/policies/web/company/projects/skills_policy.rb
- app/policies/web/company/projects/tools_policy.rb
- app/policies/web/company/projects/workflow_run_assets_policy.rb
- app/policies/web/company/projects/workflow_runs_policy.rb
- app/policies/web/company/projects/workflows_policy.rb
- app/policies/web/company/projects/board/activities_policy.rb
- app/policies/web/company/projects/board/columns_policy.rb
- app/policies/web/company/projects/board/tasks_policy.rb
- app/policies/web/company/projects/board/view_presets_policy.rb
- app/policies/web/company/projects/board/task/activities_policy.rb
- app/policies/web/company/projects/board/task/assets_policy.rb
- app/policies/web/company/projects/board/task/comments_policy.rb
- app/policies/web/company/projects/board/task/statistics_policy.rb
- app/policies/web/company/projects/board/task/transitions_policy.rb
- app/policies/web/company/projects/board/task/waits_policy.rb
- app/policies/web/company/projects/workflows/steps_policy.rb

Modified files:
- app/controllers/web/company/application_controller.rb (added `before_action :dynamic_authorize!`)
- app/controllers/web/company/projects/application_controller.rb (added `policy_context` override, reordered callbacks)
- app/controllers/web/company/members_controller.rb (removed 4 explicit `authorize` calls)
- app/controllers/web/company/integrations_controller.rb (added `skip_before_action :dynamic_authorize!, only: :github_setup`)
- test/integration/web/company/agents_controller_test.rb (added `role: :admin`)
- test/integration/web/company/assets_controller_test.rb (added `role: :admin`)
- test/integration/web/company/config_items_controller_test.rb (added `role: :admin`)
- test/integration/web/company/integrations_controller_test.rb (added `role: :admin`)
- test/integration/web/company/mcp_servers_controller_test.rb (added `role: :admin`)
- test/integration/web/company/members_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects_controller_test.rb (added `role: :admin`)
- test/integration/web/company/repositories_controller_test.rb (added `role: :admin`)
- test/integration/web/company/sessions_controller_test.rb (added `role: :admin`)
- test/integration/web/company/skills_controller_test.rb (added `role: :admin`)
- test/integration/web/company/tools_controller_test.rb (added `role: :admin`)
- test/integration/web/company/workflows_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/agents_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/analytics_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/boards_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/config_items_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/integrations_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/mcp_servers_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/members_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/overview_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/repositories_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/sessions_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/settings_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/skills_controller_test.rb (added `role: :admin`)
- test/integration/web/company/projects/tools_controller_test.rb (added `role: :admin`)
