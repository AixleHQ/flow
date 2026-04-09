# E3: Policies via dynamic_authorize! — Full Authorization Layer

## Overview

Wire Pundit authorization into all web controllers using `dynamic_authorize!`. Rewrite `AuthorizationConcern` so it correctly resolves record + policy from controller context. Add policies for all resource types. Pass permission props to frontend via Inertia shared data.

---

## Problem Statement

### Current State

1. **`AuthorizationConcern`** defines `dynamic_authorize!` but it's broken:
   - `init_authorize` generates a method that calls `authorize([:web, :company, :agents])` — passing an array of symbols instead of a record + query
   - This doesn't match Pundit's API: `authorize(record, query = nil, policy_class: nil)`
   - Nobody calls `dynamic_authorize!` — it's dead code

2. **Only `MembersController`** uses `authorize` — with explicit `policy_class:` argument

3. **Policies exist** for: `ApplicationPolicy`, `CompanyPolicy`, `MemberPolicy`, `ProjectPolicy` — but only MemberPolicy is used

4. **Frontend** uses `currentUser.role === 'admin'` for UI gating — no policy-derived permissions

### Goal

- Fix `AuthorizationConcern` so `dynamic_authorize!` works correctly
- Add `before_action :dynamic_authorize!` to all company and project-scoped controllers
- Create missing policies for resource types that need special rules
- Pass permission flags via Inertia shared data for frontend UI gating

---

## Architecture Design

### How dynamic_authorize! Should Work

The key insight: in a company-scoped app, the "record" for authorization is either:
- **`current_company`** — for company-level controllers (agents, tools, skills, etc.)
- **`@project`** — for project-level controllers
- **A specific record** — for `show`/`update`/`destroy` on a specific resource

The "policy" should be determined by the **resource type** (derived from controller name), not the namespace.

### Proposed AuthorizationConcern Rewrite

```ruby
module AuthorizationConcern
  extend ActiveSupport::Concern

  included do
    prepend_before_action :init_authorize
  end

  def dynamic_authorize!
    record = resolve_authorization_record
    authorize record, policy_class: resolve_policy_class
  end

  def pundit_user
    policy_context
  end

  private

  def init_authorize
    # No-op — kept for backward compatibility
    # dynamic_authorize! is called explicitly via before_action
  end

  def resolve_authorization_record
    # For member actions (show, edit, update, destroy) on a specific resource:
    # try to find an instance variable matching the controller's singular resource name
    if member_action? && authorization_record_ivar
      instance_variable_get(authorization_record_ivar)
    elsif project_scoped?
      @project
    else
      current_company
    end
  end

  def resolve_policy_class
    # Derive from controller name: Web::Company::AgentsController → AgentPolicy (if exists)
    # Fallback: CompanyPolicy for company-scoped, ProjectPolicy for project-scoped
    resource_policy_class || fallback_policy_class
  end

  def resource_policy_class
    policy_name = controller_resource_name.classify + "Policy"
    policy_name.safe_constantize
  end

  def fallback_policy_class
    project_scoped? ? CompanyPolicy : CompanyPolicy
  end

  def controller_resource_name
    # Web::Company::AgentsController → "agent"
    # Web::Company::Projects::ToolsController → "tool"
    controller_name.singularize
  end

  def project_scoped?
    self.class.ancestors.any? { |a| a == Web::Company::Projects::ApplicationController }
  end

  def member_action?
    action_name.in?(%w[show edit update destroy])
  end

  def authorization_record_ivar
    ivar = "@#{controller_resource_name}"
    instance_variable_defined?(ivar) ? ivar : nil
  end
end
```

### Policy Resolution Matrix

| Controller Level | Record | Policy | Fallback |
|-----------------|--------|--------|----------|
| Company CRUD (agents, tools, etc.) | `current_company` for index/create; `@agent` for show/update/destroy | `AgentPolicy` if exists, else `CompanyPolicy` | `CompanyPolicy` |
| Project CRUD (project agents, tools, etc.) | `@project` for index/create; `@tool` for show/update/destroy | `ToolPolicy` if exists, else `CompanyPolicy` | `CompanyPolicy` |
| Board nested | `@project` (via board → project) | `CompanyPolicy` | `CompanyPolicy` |
| Members (company) | `current_company` for index/create; `@user` for update/destroy | `MemberPolicy` | already works |
| Members (project) | `@project` for index/create | `CompanyPolicy` | `CompanyPolicy` |

### Which Policies Do We Need?

Most resources use the same rule: **member of the company can CRUD**. So `CompanyPolicy` (which checks `member?`) is the correct default for most controllers.

**Special policies already exist:**
- `MemberPolicy` — admin-only for create/update, no self-delete
- `ProjectPolicy` — `accessible_by?` for show, owner/admin for destroy

**New policies needed:**
- None for now — `CompanyPolicy` covers agents, tools, skills, mcp_servers, config_items, integrations, repositories, assets, workflows, sessions, boards, board columns, board tasks. All these follow the "member can do everything" rule.

If future requirements need per-resource policies (e.g. "only admins can create tools"), we create `ToolPolicy < CompanyPolicy` and override specific methods. The `resolve_policy_class` logic will automatically pick it up.

---

## Stories

### Story 3.1: Rewrite AuthorizationConcern

**Goal:** Fix `dynamic_authorize!` to correctly resolve record and policy class from controller context.

**Changes:**

1. Rewrite `app/controllers/concerns/authorization_concern.rb` per the design above
2. Keep `pundit_user → policy_context` (this works correctly)
3. Remove `init_authorize` body (no longer generates broken methods)
4. Add `resolve_authorization_record`, `resolve_policy_class`, `controller_resource_name`, `project_scoped?`, `member_action?`

**Testing approach:**
- Run existing `MembersController` test to verify it still works
- Manual smoke test of a few controllers

**Acceptance Criteria:**
- [ ] `dynamic_authorize!` resolves correct record and policy for company controllers
- [ ] `dynamic_authorize!` resolves correct record and policy for project controllers
- [ ] `MembersController` still uses explicit `authorize` with `policy_class:` (no regression)
- [ ] No existing tests broken

### Story 3.2: Add before_action :dynamic_authorize! to Company Controllers

**Goal:** Wire authorization into all company-scoped controllers.

**Controllers to update (add `before_action :dynamic_authorize!`):**

- `Web::Company::AgentsController`
- `Web::Company::ToolsController`
- `Web::Company::SkillsController`
- `Web::Company::MCPServersController`
- `Web::Company::ConfigItemsController`
- `Web::Company::IntegrationsController`
- `Web::Company::RepositoriesController`
- `Web::Company::AssetsController`
- `Web::Company::WorkflowsController`
- `Web::Company::SessionsController`
- `Web::Company::ProjectsController`

**Note:** `MembersController` already has explicit `authorize` calls — keep those, skip `dynamic_authorize!` or let both coexist (Pundit doesn't complain about double-authorize).

**For each controller:**
1. Add `before_action :dynamic_authorize!`
2. Ensure instance variables are set before authorize runs (e.g., `@agent` is set in `before_action :set_agent` which must run BEFORE `dynamic_authorize!`)
3. If the controller uses `before_action :set_X, only: [...]` — make sure `dynamic_authorize!` runs after it for member actions

**Pattern:**
```ruby
class Web::Company::AgentsController < Web::Company::ApplicationController
  before_action :set_agent, only: %i[update destroy]
  before_action :dynamic_authorize!
  # ...
end
```

**Acceptance Criteria:**
- [ ] All company controllers have `before_action :dynamic_authorize!`
- [ ] Authorization passes for company members
- [ ] Unauthenticated requests redirect to login
- [ ] All existing integration tests pass

### Story 3.3: Add before_action :dynamic_authorize! to Project Controllers

**Goal:** Wire authorization into all project-scoped controllers.

**Controllers to update:**

- `Web::Company::Projects::OverviewController`
- `Web::Company::Projects::AnalyticsController`
- `Web::Company::Projects::SettingsController`
- `Web::Company::Projects::MembersController`
- `Web::Company::Projects::RepositoriesController`
- `Web::Company::Projects::IntegrationsController`
- `Web::Company::Projects::ConfigItemsController`
- `Web::Company::Projects::AssetsController`
- `Web::Company::Projects::SkillsController`
- `Web::Company::Projects::ToolsController`
- `Web::Company::Projects::AgentsController`
- `Web::Company::Projects::MCPServersController`
- `Web::Company::Projects::SessionsController`
- `Web::Company::Projects::WorkflowsController`
- `Web::Company::Projects::WorkflowRunsController`
- `Web::Company::Projects::WorkflowRunAssetsController`
- `Web::Company::Projects::AixleBuilderController`
- `Web::Company::Projects::BoardsController`

**Board nested controllers** (inherit from Board::ApplicationController):
- `Board::ColumnsController`
- `Board::TasksController`
- `Board::ViewPresetsController`
- `Board::ActivitiesController`

**Board task nested:**
- `Board::Task::*` (all 6 controllers)

**Workflow steps nested:**
- `Projects::Workflows::StepsController`
- `Company::Workflows::StepsController`

**Acceptance Criteria:**
- [ ] All project-scoped controllers have `before_action :dynamic_authorize!`
- [ ] Project access uses existing scoping (`Project.for_user`) plus policy check
- [ ] All existing integration tests pass

### Story 3.4: Frontend Permission Props via Inertia Shared Data

**Goal:** Pass permission flags to the frontend so UI can gate features based on server-side policy evaluation.

**Approach:**

Add to `Web::Company::ApplicationController` shared data:

```ruby
inertia_share do
  if signed_in?
    {
      permissions: InertiaRails.always {
        {
          can_manage_members: MemberPolicy.new(policy_context, current_company).create?,
          can_manage_projects: CompanyPolicy.new(policy_context, current_company).create?,
          is_admin: current_user.role.admin? || current_user.role.super_admin?
        }
      }
    }
  end
end
```

**Frontend usage:**
```tsx
const { permissions } = usePage().props;
// permissions.canManageMembers, permissions.canManageProjects, permissions.isAdmin
```

**Acceptance Criteria:**
- [ ] `permissions` object available on all company/project pages
- [ ] `canManageMembers` reflects MemberPolicy
- [ ] Frontend `AppHeader` uses `permissions.isAdmin` instead of `currentUser.role === 'admin'`
- [ ] TypeScript type for `permissions` generated via Typelizer/Alba

---

## Implementation Order

1. **Story 3.1** — Rewrite concern (foundation)
2. **Story 3.2** — Company controllers (safe, existing tests verify)
3. **Story 3.3** — Project controllers (bigger scope, run full test suite)
4. **Story 3.4** — Frontend permissions (UX improvement, non-blocking)

---

## Technical Notes

### before_action ordering

Rails runs `before_action` in the order they're defined. For member actions, the record must be loaded before `dynamic_authorize!` runs:

```ruby
before_action :set_agent, only: %i[show update destroy]  # loads @agent
before_action :dynamic_authorize!                          # uses @agent for member actions
```

For collection actions (index, create), `dynamic_authorize!` will use `current_company` or `@project` — no specific record needed.

### Controllers with skip_before_action

Some controllers may need to skip authorization for specific actions (e.g., public pages). Use:
```ruby
skip_before_action :dynamic_authorize!, only: %i[some_action]
```

### Existing MembersController

The existing explicit `authorize` calls in `MembersController` can coexist with `dynamic_authorize!` from the base controller. However, for clarity, we may want to either:
- Keep explicit `authorize` and skip `dynamic_authorize!` on MembersController
- Or remove explicit `authorize` and rely on `dynamic_authorize!` with `MemberPolicy` auto-resolution

Recommendation: **keep explicit** for MembersController since it has non-standard logic (different policy_class per action, explicit record selection).

### Session controllers

`Web::SessionsController` (login/logout) does NOT inherit from `Web::Company::ApplicationController` — it's under `Web::ApplicationController` directly, so no `dynamic_authorize!`. Same for `Web::HomeController`, `Web::PagesController`, `Web::OnboardingController`.

`Web::TerminalSessionsController` inherits from `Web::ApplicationController` — if we want auth there, it needs its own policy or skip.
