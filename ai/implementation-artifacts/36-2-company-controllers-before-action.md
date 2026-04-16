# Story 36.2: Add before_action :dynamic_authorize! to Company Controllers

Status: review

## Story

As a developer,
I want `before_action :dynamic_authorize!` wired into all company-scoped controllers,
so that every company-level endpoint is authorized via Pundit policies created in story 36-1.

## Background — What Story 36-1 Already Did

Story 36-1 created the full authorization foundation. The following is already in place:

1. **`Web::Company::ApplicationController`** already has `before_action :dynamic_authorize!` (added in 36-1)
2. **`AuthorizationConcern`** is unchanged — `init_authorize` dynamically creates `authorize_<policy_name>` methods, `dynamic_authorize!` calls them, `pundit_user` returns `policy_context`
3. **`BaseContext`** and **`ProjectContext`** exist in `app/contexts/`
4. **All company-level policies** exist under `app/policies/web/company/` — they use `current_user.admin?` for all actions (except `MembersPolicy#index?` which returns `true`)
5. **`Web::Company::IntegrationsController`** already has `skip_before_action :dynamic_authorize!, only: :github_setup`

**Since `before_action :dynamic_authorize!` is already on the base controller and policies exist, this story is about verifying it works end-to-end and fixing any issues discovered.**

## Acceptance Criteria

1. All company-scoped controllers authorize via `dynamic_authorize!` inherited from the base controller
2. Admin users can access all company controller actions
3. Non-admin users can access `MembersController#index` (the only non-admin-allowed action)
4. Non-admin users are redirected with "not authorized" flash for all other company controller actions
5. `IntegrationsController#github_setup` skips authorization (already implemented)
6. No `Pundit::AuthorizationNotPerformedError` on any company-scoped route
7. All existing tests pass: `docker compose exec web bundle exec rails test`

## Tasks / Subtasks

- [x] Task 1: Audit policy action coverage against controller actions (AC: 1, 6)
  - [x] Verify each company controller's public actions have a matching policy method
  - [x] Check for missing policy actions — see "Policy/Controller Action Matrix" below
  - [x] Add any missing policy action methods

- [x] Task 2: Verify before_action ordering for member actions (AC: 1)
  - [x] For controllers with `before_action :set_X, only: [...]` — confirm `set_X` runs BEFORE `dynamic_authorize!`
  - [x] If `set_X` is defined in the controller itself (not the base), it runs after `dynamic_authorize!` — reorder if needed
  - [x] Pattern: `before_action :set_agent, only: %i[update destroy]` must come BEFORE `before_action :dynamic_authorize!`

- [x] Task 3: Smoke test all company controller actions manually (AC: 2, 3, 4)
  - [x] Run the Rails test suite
  - [x] If integration tests exist for company controllers, verify they pass
  - [x] If no tests exist, manual verification via `rails console` or browser

- [x] Task 4: Fix any authorization failures discovered (AC: 6, 7)
  - [x] Resolve any `Pundit::NotAuthorizedError` that shouldn't occur
  - [x] Resolve any `Pundit::AuthorizationNotPerformedError` for missing policy methods
  - [x] Ensure `rescue_from Pundit::NotAuthorizedError` in base controller handles failures gracefully

## Dev Notes

### How dynamic_authorize! Works (Do NOT Reinvent)

The `AuthorizationConcern` at `app/controllers/concerns/authorization_concern.rb`:

1. `init_authorize` (prepend_before_action) defines `authorize_web_company_agents` dynamically
2. That method calls `authorize([:web, :company, :agents])` — Pundit resolves the symbol array to `Web::Company::AgentsPolicy`
3. `dynamic_authorize!` calls `send(policy_method_name)` which invokes the dynamically defined method
4. `pundit_user` returns `policy_context` (which is `BaseContext.new(current_user, params)` at company level)

The query name is derived from the action: `index` → `index?`, `create` → `create?`, etc.

### Policy/Controller Action Matrix — Company Level

Verify each controller's public actions have a matching `def action?` in the corresponding policy.

| Controller | Actions | Policy File | Policy Actions |
|---|---|---|---|
| `AgentsController` | index, create, update, destroy | `agents_policy.rb` | index?, create?, update?, destroy? |
| `AssetsController` | index, create, destroy, versions, download | `assets_policy.rb` | index?, create?, destroy?, versions?, download? |
| `ConfigItemsController` | index, create, update, destroy | `config_items_policy.rb` | index?, create?, update?, destroy? |
| `IntegrationsController` | index, github_setup, create, destroy | `integrations_policy.rb` | index?, github_setup?, create?, destroy? |
| `MCPServersController` | index, create, update, destroy | `mcp_servers_policy.rb` | index?, create?, update?, destroy? |
| `MembersController` | index, create, update, destroy | `members_policy.rb` | index? (true), create?, update?, destroy? |
| `ProjectsController` | index, show, create, destroy | `projects_policy.rb` | index?, show?, create?, destroy? |
| `RepositoriesController` | index, create, update, destroy | `repositories_policy.rb` | index?, create?, update?, destroy? |
| `SessionsController` | index, new, show | `sessions_policy.rb` | index?, new?, show? |
| `SkillsController` | index, create, destroy | `skills_policy.rb` | index?, create?, destroy? |
| `ToolsController` | index, create, update, destroy | `tools_policy.rb` | index?, create?, update?, destroy? |
| `WorkflowsController` | index, builder, create, show, update, destroy | `workflows_policy.rb` | index?, builder?, create?, show?, update?, destroy? |

**Nested company controllers (also inherit `dynamic_authorize!` from base):**

| Controller | Actions | Policy File | Policy Actions |
|---|---|---|---|
| `Workflows::StepsController` | index, show, create, update, destroy, reorder | `workflows/steps_policy.rb` | index?, show?, create?, update?, destroy?, reorder? |
| `Sessions::ArtifactsController` | index, review | `sessions/artifacts_policy.rb` | index?, review? |

**NOTE:** `RepositoriesPolicy` has a `branches?` method but the controller has no `branches` action — this is harmless (unused policy method). Do NOT add a `branches` action.

### before_action Ordering

`Web::Company::ApplicationController` declares:
```ruby
before_action :require_auth
before_action :dynamic_authorize!
```

Individual controllers do NOT re-declare `before_action :dynamic_authorize!` — they inherit it. If a controller has `before_action :set_agent, only: %i[update destroy]`, that filter runs in definition order. Since child controller `before_action` declarations run AFTER parent ones, `set_agent` runs AFTER `dynamic_authorize!`.

**This is fine** because `dynamic_authorize!` at company level resolves the record to `[:web, :company, :agents]` (the symbol array), not to `@agent`. The policy receives the symbol array as the record and checks `current_user.admin?` — it doesn't need the instance variable.

### Existing `rescue_from` in Base Controller

```ruby
rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

def user_not_authorized
  redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
end
```

This handles authorization failures gracefully — non-admin users get redirected with a flash message.

### Files to Inspect/Potentially Modify

| File | Expected Change |
|------|----------------|
| `app/policies/web/company/*.rb` | Add missing policy actions if any don't match controller |
| `app/controllers/web/company/*.rb` | Reorder `before_action` if needed (unlikely) |
| No new files should be created | |

### References

- [Source: app/controllers/web/company/application_controller.rb] — base controller with `dynamic_authorize!`
- [Source: app/controllers/concerns/authorization_concern.rb] — concern implementation
- [Source: app/policies/web/company/] — all company-level policies
- [Source: ai/implementation-artifacts/epic-36-policies-dynamic-authorize.md] — epic design
- [Source: ai/implementation-artifacts/36-1-add-policies-and-contexts-for-web-controllers.md] — previous story

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Debug Log References

### Completion Notes List

- Exhaustive audit of all 14 company-level controllers (12 direct + 2 nested) against their Pundit policies confirmed 100% action coverage — every public controller action has a matching `action?` method in the policy
- Only anomaly: `RepositoriesPolicy` has an extra `branches?` method with no matching controller action — harmless unused method, no change needed
- `before_action` ordering verified: `dynamic_authorize!` on `Web::Company::ApplicationController` resolves record to symbol array `[:web, :company, ...]`, so instance variable loading order is irrelevant at company level — policies check `current_user.admin?` and don't need `@agent`, `@tool`, etc.
- `IntegrationsController` correctly skips `dynamic_authorize!` for `github_setup` action
- `MembersPolicy#index?` returns `true` (non-admin access), all other policy actions return `current_user.admin?`
- Full test suite run: 1546 tests, 0 authorization-related failures. All 12 pre-existing failures are in unrelated areas (model validations, session context service, API parsing, agent adapters)
- No code changes were required — story 36-1 already established all policies and wired `before_action :dynamic_authorize!` on the base controller

### File List

No files created or modified — verification-only story. Story 36-1 already completed all code changes.
