# Technical Design — #211 Restrict permissions: project deletion, company analytics, company sessions

## 1. Problem & Goal

Three Pundit policies in the company namespace are too permissive, letting `employee`-role
members (and, in the case of project deletion, any project collaborator) perform actions that
should be reserved for the project owner or a company admin:

- **G1 — Project deletion.** `Web::Company::ProjectsPolicy#destroy?` authorizes any user who
  `accessible_by?` the project, which includes collaborators and company admins
  (`app/policies/web/company/projects_policy.rb:18-20`). A non-owner collaborator can delete a
  project.
- **G2 — Company analytics.** `Web::Company::AnalyticsPolicy#index?` is hardcoded `true`
  (`app/policies/web/company/analytics_policy.rb:6`). Any authenticated member sees company-wide
  cost/token analytics.
- **G3 — Company sessions.** `Web::Company::SessionsPolicy` returns `true` for `index?`, `new?`,
  and `show?` (`app/policies/web/company/sessions_policy.rb:6-8`). Any member can list and view
  every session across the company.

**Goal:** tighten exactly these three policies to the role/ownership boundary described in the
issue, mirror the existing admin-gated policy pattern already used by
`Web::Company::MembersPolicy` (`app/policies/web/company/members_policy.rb:10-20`), keep the UI
consistent (hide nav links / the delete button the policies now reject), and add focused tests.
**No data-model change**, no migration.

## 2. Current State (how it works today)

### 2.1 How a policy gets invoked (the dynamic-authorize mechanism)

Company web controllers inherit `Web::Company::ApplicationController`
(`app/controllers/web/company/application_controller.rb`), which:

- `include AuthorizationConcern` and `include Pundit::Authorization` (lines 4-5).
- runs `before_action :dynamic_authorize!` (line 10).
- on a `Pundit::NotAuthorizedError`, runs `rescue_from … with: :user_not_authorized` (line 12).

`AuthorizationConcern` (`app/controllers/concerns/authorization_concern.rb`) derives the policy and
the authorize call from the controller class name:

- `policy_name` underscores the class minus `::`/`Controller`
  (`authorization_concern.rb:30-34`) → for `Web::Company::AnalyticsController` it produces
  `web_company_analytics`.
- `policy_method_params` turns the class into a symbol array
  (`authorization_concern.rb:36-41`) → `[:web, :company, :analytics]`.
- `dynamic_authorize!` calls `authorize([:web, :company, :analytics])`
  (`authorization_concern.rb:13-18`). Pundit resolves the policy from the namespaced array
  (`Web::Company::AnalyticsPolicy`) and uses the default query `"#{action_name}?"`. So `GET
  /company/analytics` (action `index`) → `Web::Company::AnalyticsPolicy#index?`.
- `pundit_user` is overridden to `policy_context` (`authorization_concern.rb:20-22`), and
  `policy_context` returns `BaseContext.new(current_user, params)`
  (`application_controller.rb:28-30`).

`BaseContext` exposes `user` and `params` (`app/contexts/base_context.rb`).
`Web::Company::ApplicationPolicy#current_user` returns `context.user`
(`app/policies/web/company/application_policy.rb:8-10`); `ApplicationPolicy#user` does the same
(`app/policies/application_policy.rb:11-13`).

**Important consequence:** `dynamic_authorize!` is a `before_action`, so the policy gate runs
*before* the controller body. The fix is purely in the policy objects.

### 2.2 G1 — Project deletion

- Policy: `app/policies/web/company/projects_policy.rb:18-20`
  ```ruby
  def destroy?
    current_project&.accessible_by?(current_user)
  end
  ```
  Its private `current_project` re-fetches from `current_user.company.projects.find_by(id:
  context.params[:id])` (`projects_policy.rb:24-28`) — it reads `:id` from params and does **not**
  rely on a `ProjectContext` (the company-level policy uses `BaseContext`).
- `Project#accessible_by?(user)` returns `true` for owner OR collaborator OR same-company admin
  (`app/models/project.rb:80-87`).
- `Project#admin?(user)` is owner-only: `owner_id == user.id` (`app/models/project.rb:90-92`).
- Controller: `Web::Company::ProjectsController#destroy` does `Project.for_user(current_user).find(params[:id]); project.destroy!` (`app/controllers/web/company/projects_controller.rb:35-39`).
- `Project.for_user` (`app/models/project.rb:52-58`): admins get every project in their company;
  non-admins get owned + collaborated projects. So a collaborator's `find` succeeds, the policy's
  `accessible_by?` returns `true`, and the delete goes through. **This is the bug.**
- Route: `DELETE /company/projects/:id` (`config/routes.rb:203`, `resources :projects, only:
  %i[index show create destroy]`).
- Frontend trigger: the only delete entry point is the project **Settings** "Danger Zone"
  (`app/frontend/pages/Projects/Settings/SettingsPage.tsx:176-199`), which `router.delete(
  '/company/projects/${project.id}')`. The Delete button (`SettingsPage.tsx:481-490`) is shown to
  anyone who can view Settings. Settings visibility is `project.accessible_by?(current_user)`
  (`app/policies/web/company/projects/settings_policy.rb:7,14-16`) — i.e. collaborators see the
  Delete button today. Note this policy reads `context.project` (`settings_policy.rb:12`), i.e. the
  per-project `ProjectContext`, which is a **different** context from the company-level `BaseContext`
  that `ProjectsPolicy` uses — do not conflate the two. The `SettingsController#show` props do **not**
  include any current-user ownership/permission flag
  (`app/controllers/web/company/projects/settings_controller.rb:26-45`); the `members` array carries
  a per-member `is_owner` but nothing about the viewer (`settings_controller.rb:47-56`).

  **Out of scope for #211 (confirm with product):** this design hides only the Settings **Delete
  button**, not the Settings **page**. `SettingsPolicy#show?` stays `project.accessible_by?`
  (`settings_policy.rb:7`), so a collaborator can still open Settings and read owner email, member
  list, and the various counts — they just can't see/trigger Delete. If "restrict permissions" is
  meant to be page-level (collaborators should not see Settings at all), that is a larger,
  separate change to `SettingsPolicy#show?` and is not part of this issue. See §5.

### 2.3 G2 — Company analytics

- Policy: `app/policies/web/company/analytics_policy.rb:6` → `def index? = true`.
- Controller: `Web::Company::AnalyticsController#index` renders `Company/Analytics/AnalyticsPage`
  with deferred props (`app/controllers/web/company/analytics_controller.rb:4-59`). Data is
  company-scoped via `CompanyAnalyticsService` et al.
- Route: `GET /company/analytics` (`config/routes.rb:258`, `resources :analytics, only: :index`).
- Frontend nav: the "Analytics" item in `companyNavGroups` (group body
  `app/frontend/shared/ui/AppSidebar.tsx:139-162`) is **not** `adminOnly` (`AppSidebar.tsx:146`), so
  employees see and can click it.
- (Note: the project-scoped analytics — `web/company/projects/analytics_policy.rb`, route
  `config/routes.rb:237` — is a different resource and out of scope for #211.)

### 2.4 G3 — Company sessions

- Policy: `app/policies/web/company/sessions_policy.rb:6-8` → `index?`, `new?`, `show?` all `true`.
- Controller: `Web::Company::SessionsController` defines only `index` and `show`
  (`app/controllers/web/company/sessions_controller.rb:4-37`); scope is company-wide via
  `company_sessions_scope` (`application_controller.rb:48-52`).
- Routes: `GET /company/sessions` and `GET /company/sessions/:id` only —
  `resources :sessions, only: %i[index show]` (`config/routes.rb:260`). **There is no `new`/`create`
  route at the company level** and no `new`/`create` controller action. The policy's `new?` is
  effectively dead at this namespace. (The project-scoped sessions resource at
  `config/routes.rb:207` does allow `new` but is governed by a different policy,
  `web/company/projects/sessions_policy.rb`.)
- Frontend nav: the "Sessions" item in `companyNavGroups` is **not** `adminOnly`
  (`app/frontend/shared/ui/AppSidebar.tsx:147`).

### 2.5 What "unauthorized" actually returns on the web (critical)

`Web::Company::ApplicationController#user_not_authorized` does
`redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."`
(`application_controller.rb:32-34`). That is an **HTTP 302 redirect**, not a 403. The 403/`:forbidden`
JSON response only exists in the API namespace
(`app/controllers/api/v1/application_controller.rb:26-28`), which is unrelated to these three web
routes. **The issue's acceptance criteria say "receives 403"; the actual web behavior is a 302
redirect with an alert flash.** This is not a defer-able open question — it is a **blocking
pre-implementation decision (DECISION 1, §5)**: the AC checkboxes ("receives 403") and the test
assertions are mutually contradictory until product picks 302-or-403, and the AC cannot be marked
done as written either way. **Resolve DECISION 1 before writing any code or tests.**

### 2.6 Role model & who reaches these routes

- `User#role` is `enumerize … in: %i[employee admin super_admin]` with predicates
  (`app/models/user.rb:20`); `current_user.admin?` is true only for the `admin` role.
- `super_admin` users never reach company routes: `Web::ApplicationController` has
  `before_action :redirect_super_admin_to_admin_panel` which `redirect_to admin_root_path` for any
  signed-in super admin (`app/controllers/web/application_controller.rb` —
  `redirect_super_admin_to_admin_panel`). So at runtime the only callers of these company policies
  are `employee` and `admin`. `current_user.admin?` therefore fully expresses "admin-only" for these
  routes without needing `|| super_admin?`. See §5 OPEN QUESTION 2.

### 2.7 Existing tests & patterns to mirror

- Model: `test/models/project_test.rb` already covers `accessible_by?` for owner/collaborator/admin/
  stranger/foreign-admin (lines 12-37). It does **not** cover `admin?(user)`.
- Integration tests exist and currently only sign in an **admin** and assert success:
  `test/integration/web/company/projects_controller_test.rb`,
  `test/integration/web/company/analytics_controller_test.rb`,
  `test/integration/web/company/sessions_controller_test.rb`. All `setup` blocks use the
  `:admin, :onboarding_completed` traits (e.g. `projects_controller_test.rb:8`). **Caveat for the
  destroy test:** `projects_controller_test.rb:22-26` creates the project with `owner: @user` where
  `@user` is the signed-in admin (`:23`), so the admin is **also the owner** — the existing test
  passes via the **owner** branch of `destroy?`, *not* the company-admin branch. It therefore does
  **not** prove that a company admin who is **not** the owner can delete; that branch needs a new
  integration case (§7.3).
- There is **no** `test/policies/` directory and **no** `*_policy_test.rb` anywhere
  (verified). Policies are currently exercised only through integration tests.
- Admin-gating pattern to mirror: `Web::Company::MembersPolicy` uses `current_user.admin?` (and a
  `same_company?` helper) (`app/policies/web/company/members_policy.rb:10-28`).
- Frontend admin-gating pattern to mirror: nav items flagged `adminOnly: true` are filtered by
  `SidebarNav` via `group.items.filter((item) => !item.adminOnly || isAdmin)`
  (`AppSidebar.tsx:81, 157-158, 179`); `isAdmin` comes from shared `permissions.isAdmin`
  (`AppSidebar.tsx:470`, sourced from `application_controller.rb:16-23`). FE tests for this live in
  `app/frontend/shared/ui/AppSidebar.test.tsx:59-80` with the `buildSharedPermissions` factory
  (`app/frontend/test/factories/sharedProps.ts:44-49`).

## 3. Proposed Design (approach + rationale)

Apply the minimal three-policy change the issue prescribes, then make two consistency follow-ups so
the UI does not advertise actions the backend will now reject.

1. **Policies (the actual fix).** Edit the three policy files only. Mirror `MembersPolicy`'s
   `current_user.admin?` idiom for the analytics/sessions gates, and use the project's own
   ownership predicate `Project#admin?(user)` (owner-only) OR `current_user.admin?` for project
   deletion. Keep using the existing `current_project` helper in `ProjectsPolicy` (it already
   re-fetches scoped to the user's company).

2. **Frontend nav consistency (G2/G3).** Mark the company "Analytics" and "Sessions" nav items
   `adminOnly: true` so employees no longer see links to pages that now 302-redirect them away.
   This reuses the existing `adminOnly` mechanism — no new plumbing.

3. **Frontend Delete-button consistency (G1).** Hide the Settings "Danger Zone" Delete button when
   the viewer is neither the project owner nor a company admin, by passing a `can_delete` flag from
   `SettingsController#show` and gating the button on it. This mirrors how the policy decides
   (`current_project.admin?(current_user) || current_user.admin?`). The button is a convenience
   guard only; the policy remains the source of truth.

**Why a backend-computed `can_delete` flag rather than reusing `permissions.isAdmin`?** Deletion is
allowed for the project **owner** too, and ownership is per-project — the shared `permissions`
object only knows company-level admin status (`application_controller.rb:16-23`). The owner case
must be computed server-side against the specific project, exactly as the policy does.

### Rejected alternatives

- **Return a real 403 from `user_not_authorized`.** Rejected as the *default* for this issue: it
  would change the global behavior of *every* company web policy failure (currently a friendly
  redirect-with-alert), which is broad and risky. But this is a **blocking decision, not a settled
  rejection** — it is escalated as DECISION 1 (§5) and must be resolved by product before code is
  written, because the issue's AC literally say "403". If product confirms 302+alert, the tests
  assert the real behavior (302 + alert); if product wants 403, see DECISION 1 for the scoping.
- **Add `|| current_user.super_admin?` to the gates.** Rejected: super admins are redirected to the
  admin panel before reaching company routes (`redirect_super_admin_to_admin_panel`), so the clause
  is dead code and would diverge from the `MembersPolicy` precedent. Flagged as OPEN QUESTION 2.
- **Gate the Delete button purely client-side off member ownership data.** The Settings page already
  receives a `members` array with `is_owner`, but it has no reliable "who am I" identifier to match
  against, and it would not account for the company-admin case. A server-computed boolean is simpler
  and authoritative.
- **Remove the dead `new?` from `SessionsPolicy`.** Tempting cleanup, but the issue explicitly lists
  `new?` in the required behavior; we keep it and set it to `current_user.admin?` so the policy is
  correct even though no company-level `new` route exists. Flagged in §5.

## 4. Detailed Changes

### Backend

#### Policy — `app/policies/web/company/projects_policy.rb` (G1)

Replace `destroy?` (lines 18-20). Keep everything else.

```ruby
def destroy?
  return false unless current_project

  current_project.admin?(current_user) || current_user.admin?
end
```

- `current_project.admin?(current_user)` → owner-only (`Project#admin?`, `project.rb:90-92`).
- `current_user.admin?` → company admin (`User` enumerize predicate, `user.rb:20`). The
  `current_project` helper already scopes to `current_user.company.projects`
  (`projects_policy.rb:24-28`), so a company admin only matches projects in their own company; a
  cross-company id returns `nil` → `false`. No extra same-company guard needed.
- `index?`, `show?`, `create?` are unchanged.

#### Policy — `app/policies/web/company/analytics_policy.rb` (G2)

```ruby
def index? = current_user.admin?
```

(replaces `def index? = true`, line 6.)

#### Policy — `app/policies/web/company/sessions_policy.rb` (G3)

```ruby
def index? = current_user.admin?
def new?   = current_user.admin?
def show?  = current_user.admin?
```

(replaces the three `true` definitions, lines 6-8.)

#### Controller — `app/controllers/web/company/projects/settings_controller.rb` (G1 UI support)

Add a single computed prop in `settings_project_props` (after line 43, inside the returned hash) so
the page can hide the Delete button for non-owner/non-admin viewers. This mirrors the policy's
decision:

```ruby
# inside settings_project_props, add to the returned hash:
can_delete: project.admin?(current_user) || current_user.admin?
```

`current_user` is available via the controller; `project` is `current_project`. No change to
`SettingsPolicy#show?` (collaborators may still view settings).

#### Controllers — `analytics_controller.rb`, `sessions_controller.rb`, `projects_controller.rb`

No code changes. The `before_action :dynamic_authorize!` now enforces the tightened policies
automatically (see §2.1). `ProjectsController#destroy` keeps `Project.for_user(...).find` — for a
collaborator the policy now rejects before the body runs; for an admin both the policy and
`for_user` agree.

#### Routes

No changes. (`config/routes.rb` already restricts company sessions to `index/show` and analytics to
`index`.)

#### Migrations / data model

**None.** No schema or data change.

### Frontend

#### `app/frontend/shared/ui/AppSidebar.tsx` (G2/G3 nav consistency)

In `companyNavGroups` (group body lines 139-162; the two target items are at `AppSidebar.tsx:146`
and `:147`) add `adminOnly: true` to the Analytics and Sessions items:

```tsx
{ label: 'Analytics', icon: <IconChartBar size={18} />, path: '/company/analytics', adminOnly: true },
{ label: 'Sessions', icon: <IconTerminal2 size={18} />, path: companySessionsPath(), adminOnly: true },
```

`SidebarNav` already filters `!item.adminOnly || isAdmin` (line 179); `isAdmin` derives from shared
`permissions.isAdmin`. No type or plumbing change (`NavItem.adminOnly?` exists, line 81).

#### `app/frontend/pages/Projects/Settings/SettingsPage.tsx` (G1 button consistency)

1. Add `canDelete: boolean;` to the `Project` interface (after line 93). Typelizer is **not**
   involved here — `SettingsController` hand-builds the props hash (it does not serialize through an
   Alba resource), so this is an ordinary hand-maintained interface, consistent with the rest of the
   `Project` interface in this file.
2. Conditionally render the Delete row (the `<Group>` at lines 472-491) only when
   `project.canDelete` is true. Keep the Archive row visible to all (archive is not part of #211).
   The Delete button's `onClick={handleDelete}` (`SettingsPage.tsx:486`) opens a confirm modal
   (`handleDelete` at `:176`) which issues `router.delete` — gating the row hides the entire entry
   point, consistent with the policy.

```tsx
{project.canDelete && (
  <>
    <Divider color="red.9" />
    <Group justify="space-between" align="flex-start" wrap="nowrap">
      {/* …existing Delete row… */}
    </Group>
  </>
)}
```

**Note on the form resolver (do NOT "fix" it).** This file's `useForm` uses `validate:
zodResolver(schema)` at `SettingsPage.tsx:120`, which can read like a convention violation (MEMORY:
Mantine forms must use `zod4Resolver`, not bare `zodResolver`). It is **not** a violation here: the
import at `SettingsPage.tsx:38` is `import { zod4Resolver as zodResolver } from
'mantine-form-zod-resolver'` — i.e. `zodResolver` is a local **alias for `zod4Resolver`**. It already
complies with the convention. Leave it as-is; the only change to this file is adding `canDelete` and
gating the Delete row.

#### Types (generated) — no change

`ProjectResource` (`app/resources/project_resource.rb`) does **not** expose `owner_id` or
`can_delete`, and we are **not** adding fields there — the `can_delete` flag is delivered through the
hand-built `SettingsController` props, not the Alba resource. So `@/types/generated` is unaffected
and no Typelizer regeneration is required.

#### Hooks — no change

No new hooks. `isAdmin` already flows through `usePage<SharedProps>().props.permissions`.

### Data migration (if any)

None.

## 5. Edge Cases & Decisions

- **Decision (G1 cross-company admin):** the policy's `current_project` is scoped to
  `current_user.company.projects` (`projects_policy.rb:27`), so an admin of company B cannot match a
  company-A project id (`find_by` → `nil` → `destroy?` returns `false`). The AC "admin can delete
  any project within their company" is satisfied; cross-company is implicitly denied.
- **Decision (G1 owner who is also non-admin):** owner deletes via `current_project.admin?(current_user)`
  (owner-only check), independent of role. Matches AC "owner can delete their own project."
- **Decision (G1 controller find vs policy):** because `before_action :dynamic_authorize!` runs
  first, the policy rejects a collaborator before `ProjectsController#destroy`'s `Project.for_user`
  query runs. A non-collaborator stranger would already 404 in `for_user`; a collaborator now hits
  the policy 302 instead of deleting. Both are denials.
- **Decision (G3 `new?`):** there is no company-level `new`/`create` route or action
  (`config/routes.rb:260`; controller has only `index`/`show`). We still set `new? =
  current_user.admin?` per the issue, but note `POST /company/sessions` returns **404 (no route)**,
  not 403/302. The AC line "403 on `POST /company/sessions`" cannot be satisfied because that route
  does not exist. See OPEN QUESTION 3.
- **Decision (super_admin):** super admins are redirected to `/admin` before reaching these routes
  (`redirect_super_admin_to_admin_panel`), so `current_user.admin?` alone is correct. See OPEN
  QUESTION 2.
- **Edge (FE Delete button):** hiding the button is defense-in-depth only; the policy is
  authoritative. A collaborator who crafts the `DELETE` request directly is still rejected by the
  policy (302 + alert).

### BLOCKING DECISION (must be resolved by PRODUCT *before* any code/tests are written)

1. **DECISION 1 — 403 vs 302 (BLOCKING).** The issue's AC repeatedly say "receives 403," but the
   web layer's `user_not_authorized` performs a 302 redirect with an alert flash
   (`application_controller.rb:32-34`); only the API layer returns 403
   (`app/controllers/api/v1/application_controller.rb:26-28`). These two facts are mutually
   contradictory: with the codebase as-is, the AC checkbox "receives 403" can never be checked, and
   the PR's denial tests must assert *either* 302 *or* 403 — not both. **This must be decided before
   implementation**, not deferred, because it determines (a) whether any controller/`user_not_authorized`
   change is in scope at all and (b) every denial assertion in §7. Options:
   - **(a) Accept 302 + alert (recommended, minimal scope).** Keep `user_not_authorized` as-is, write
     all denial tests against `assert_response :redirect` + `flash[:alert]` + "page not rendered"
     (§7.3), and amend the AC wording from "403" to "denied (302 redirect + not-authorized alert)".
   - **(b) Return 403 for these routes.** Change `user_not_authorized` to `head :forbidden` (or render
     a 403 page). Blast radius: this changes the failure UX for **every** company web policy failure,
     not just these three — so it needs its own product sign-off and a regression sweep of other
     company controllers. If chosen, swap every §7.3 denial assertion to `assert_response :forbidden`
     and the AC-mapping "Note" column from "302 + alert" to "403".

   Until DECISION 1 is made, the AC checkboxes and the test plan cannot both be satisfied; treat the
   AC as blocked-pending-decision.

### OPEN QUESTIONS (need PRODUCT/decision input)

2. **Should super admins also pass these gates?** Today they cannot reach the routes at all
   (admin-panel redirect). If product wants super admins to view company analytics/sessions or delete
   projects via the company UI, that requires lifting `redirect_super_admin_to_admin_panel` for those
   paths — a separate, larger change. Proposed default: leave as-is (`current_user.admin?` only).
3. **`POST /company/sessions` AC.** No such route/action exists. Confirm this AC line can be dropped
   (or that it was meant to target the project-scoped sessions create, which is governed by a
   different policy and is out of scope for #211).

## 6. Acceptance Criteria Mapping

| AC (from issue) | Change that satisfies it | Note |
|---|---|---|
| Collaborator (non-owner, non-admin) is denied project delete | `ProjectsPolicy#destroy?` now `current_project.admin?(current_user) \|\| current_user.admin?` (collaborator is neither) | Denial UX is **302 + alert** today; literal "403" is blocked on DECISION 1 (§5). Note the denial 302 lands on `root_path` (the `redirect_back` fallback), **not** the projects index — see §7.3 |
| Project owner can delete their own project | `current_project.admin?(current_user)` (owner-only via `Project#admin?`) returns true | |
| Company admin (non-owner) can delete any project in their company | `current_user.admin?`, with `current_project` scoped to the admin's company | Cross-company id → `nil` → denied. **Not covered by the existing integration test** (its admin is also the owner — see row below); needs the new admin-non-owner integration case in §7.3 |
| `employee` denied `GET /company/analytics` | `AnalyticsPolicy#index? = current_user.admin?` | 302 + alert today; "403" blocked on DECISION 1 |
| `employee` denied `GET /company/sessions` | `SessionsPolicy#index? = current_user.admin?` | 302 + alert today; "403" blocked on DECISION 1 |
| `employee` denied `POST /company/sessions` | `SessionsPolicy#new? = current_user.admin?` | **No such route — 404** (OQ3); `new?` is exercised only by the policy unit test |
| `employee` denied `GET /company/sessions/:id` | `SessionsPolicy#show? = current_user.admin?` | 302 + alert today; "403" blocked on DECISION 1 |
| `admin` retains access to all three | All gates use `current_user.admin?`; for delete, admin passes via `current_user.admin?` (company-admin branch) | The existing destroy integration test (`projects_controller_test.rb:22-26`) only covers the **owner** branch (its admin **is** the owner, `:23`), so it does **not** prove the company-admin-non-owner branch — add the admin-non-owner case in §7.3. Existing analytics/sessions admin happy-path tests still pass |
| Existing `test/models/project_test.rb` passes | No change to `Project#accessible_by?`/`admin?`; only policy edits | |
| New policy unit tests for the three policies | New `test/policies/web/company/*_policy_test.rb` (see §7) | New `test/policies/` dir |

## 7. Test Plan

### 7.1 New policy unit tests (the AC's "new policy unit tests")

Create a `test/policies/web/company/` directory (none exists today). Instantiate the policy with a
`BaseContext` exactly as the controllers do (`application_controller.rb:28-30`), e.g.
`Web::Company::AnalyticsPolicy.new(BaseContext.new(user, ActionController::Parameters.new(...)), nil)`,
then assert the boolean methods. **The `record` positional is mandatory:**
`ApplicationPolicy#initialize(context, record)` (`app/policies/application_policy.rb:6`) takes two
positional args, so the `nil` second argument is required — omitting it raises `ArgumentError`.
These policies derive `current_user` from `context.user` via `Web::Company::ApplicationPolicy#current_user`
(`app/policies/web/company/application_policy.rb:8-10`; note `AnalyticsPolicy`/`SessionsPolicy` declare
no `current_user` of their own and use no `record` — the bare `ApplicationPolicy` superclass name
resolves lexically to `Web::Company::ApplicationPolicy`). Use the user/project/company factories
(`test/factories/users.rb`, `projects.rb`, `companies.rb`) and the `:employee`/`:admin` traits.

- **`test/policies/web/company/projects_policy_test.rb`** (new)
  - owner (employee role) → `destroy?` true
  - company admin (non-owner) → `destroy?` true
  - collaborator (employee, non-owner) → `destroy?` false
  - stranger employee → `destroy?` false
  - admin of another company / unknown id → `destroy?` false (`current_project` resolves `nil`)
  - sanity: `index?` true, `create?` true, `show?` true for an accessible user (regression guard)
  - Pass the project id through `params[:id]` so the policy's `current_project` resolves
    (`projects_policy.rb:25-27`).

- **`test/policies/web/company/analytics_policy_test.rb`** (new)
  - admin → `index?` true
  - employee → `index?` false

- **`test/policies/web/company/sessions_policy_test.rb`** (new)
  - admin → `index?`, `new?`, `show?` all true
  - employee → `index?`, `new?`, `show?` all false
  - **Keep the `new?` assertions.** There is no company-level `new`/`create` route or action
    (`config/routes.rb:260` is `only: %i[index show]`; the controller has only `index`/`show`), so
    this unit test is the **only** thing that exercises `SessionsPolicy#new?` — it cannot be reached
    via an integration request. Dropping `new?` from the unit test would leave it wholly unverified.

### 7.2 Model test (extend existing)

- **`test/models/project_test.rb`** — add coverage for `Project#admin?(user)`
  (`project.rb:90-92`), which the existing file does not test:
  - `admin?(owner)` → true
  - `admin?(collaborator)` → false
  - `admin?(company_admin_non_owner)` → false (owner-only, distinct from `accessible_by?`)
  This protects the owner-only semantics that `destroy?` now depends on. Existing
  `accessible_by?` tests must stay green (unchanged behavior).

### 7.3 Request / integration tests (extend existing)

The existing integration tests only sign in an admin who is **also the project owner**
(`projects_controller_test.rb:8` `:admin`, `:23` `owner: @user`). Add employee-denial cases, the
owner-allow case, **and an admin-non-owner allow case** (the existing test exercises only the owner
branch of `destroy?`, so the company-admin branch is currently unproven). Assert the **real** web
behavior (302 redirect + alert flash from `user_not_authorized`, `application_controller.rb:32-34`).
**Gated on DECISION 1 (§5):** if product resolves to "return 403," swap every denial assertion below
from `assert_response :redirect` + flash to `assert_response :forbidden`. Do not write both.

**Onboarding gotcha (applies to every new user in these tests).** `Web::ApplicationController` runs
`before_action :enforce_onboarding` (`app/controllers/web/application_controller.rb:9,52-57`), which
redirects any user whose `onboarding_state != "completed"` to `/onboarding` **before** the policy
runs. A new `:employee` user created **without** the `:onboarding_completed` trait would 302 to
onboarding and the denial test would pass for the **wrong reason** (false green — the onboarding
gate fired, not the authorization gate). Every new test user (owner, collaborator, admin-non-owner,
employee) **must** include the `:onboarding_completed` trait, matching the existing `setup` blocks
(`projects_controller_test.rb:8`).

- **`test/integration/web/company/projects_controller_test.rb`**
  - keep: admin (who is owner) destroy redirects on success (existing, lines 22-26)
  - add (**admin-non-owner**, new branch coverage): admin signs in, project owned by a **different**
    same-company user → `delete company_project_path(project)` → `assert_response :redirect`, project
    gone. This is the only case that exercises the `current_user.admin?` branch of `destroy?`.
  - add: owner (employee) can delete own project → `assert_response :redirect`, project gone. Do
    **not** assert the success redirect target — `ProjectsController#destroy` redirects via its own
    `redirect_to`/`redirect_back`, separate from the denial path.
  - add: collaborator (employee, non-owner) `delete company_project_path(project)` →
    `assert_response :redirect` **and** `assert_equal "You are not authorized to perform this action.",
    flash[:alert]`, and assert the project **still exists**.
    **Do NOT assert the denial redirect lands on `company_projects_path`.** `user_not_authorized` uses
    `redirect_back fallback_location: root_path` (`application_controller.rb:33`); an integration
    `delete company_project_path(project)` sends **no `Referer` header**, so `redirect_back` falls back
    to **`root_path`**, not the projects index. Assert only `:redirect` + the alert text (optionally
    `assert_redirected_to root_path`), never the projects index.
  - Use `create(:project, company: @company, owner: someone_else)` and
    `project.add_collaborator(current_user)`; `someone_else` and the collaborator must be
    `:onboarding_completed`.

- **`test/integration/web/company/analytics_controller_test.rb`**
  - keep existing admin tests (they sign in an admin)
  - add: an `:employee, :onboarding_completed` user signs in (`sign_in_as`), `get
    company_analytics_path` → `assert_response :redirect`, `assert_equal "You are not authorized to
    perform this action.", flash[:alert]`, **and** assert the analytics page was **not** rendered.
    Pin down that the **authorization** gate fired (a bare 302 could come from onboarding or another
    `before_action`) by asserting BOTH the specific alert text above AND that the response is not the
    page — note there is **no** `refute_inertia_page` helper (only `assert_inertia_page` at
    `test/test_helper.rb:68`, which asserts `:success`), so do **not** call a refute-helper; instead
    assert the negative directly, e.g. `assert_redirected_to root_path` (the `redirect_back` fallback,
    since the test sends no `Referer`) plus the alert text. The combination of "not a 200 success"
    (it's a 302) + the not-authorized alert + the fallback target distinguishes the auth gate from
    the happy path, which would 200-render `Company/Analytics/AnalyticsPage`.

- **`test/integration/web/company/sessions_controller_test.rb`**
  - keep existing admin tests
  - add: `:employee, :onboarding_completed` → `get company_sessions_path` → redirect + the
    not-authorized alert (`assert_equal "You are not authorized to perform this action.",
    flash[:alert]`) + assert it did not 200-render `Company/Sessions/Index` (assert the redirect +
    fallback, per the analytics note above — no `refute_inertia_page` helper exists); `get
    company_session_path(session)` → redirect + alert (it would otherwise 200-render
    `Company/Sessions/Show`)
  - (do **not** add a `POST /company/sessions` test — no route; see OQ3)

Note for both analytics & sessions: the current `setup` blocks create an **admin**
(`:admin, :onboarding_completed`) and `sign_in_as`. For the new denial cases, create a separate
`:employee, :onboarding_completed` user in the test body and `sign_in_as` that user (or restructure
with a shared helper), so the existing admin happy-path tests remain valid for the "admin retains
access" AC.

### 7.4 Frontend tests (Vitest + jsdom)

- **`app/frontend/shared/ui/AppSidebar.test.tsx`** — extend the existing admin-gating specs
  (lines 59-80, which render `context="company"`):
  - non-admin (`permissions.isAdmin = false`): assert `screen.queryByRole('link', { name:
    'Analytics' })` and `'Sessions'` are **not** in the document (alongside the existing Assets/
    Config Items assertions)
  - admin: assert both **are** present
  - **Keep these specs in the `context="company"` render.** The project-context sidebar renders its
    own "Sessions" link (`AppSidebar.test.tsx:88` already asserts a "Sessions" link in project
    context), so a "Sessions not present" assertion is only meaningful when rendered with
    `context="company"`; do not move it into a project-context render.
  - Uses `buildSharedPermissions` (`test/factories/sharedProps.ts:44-49`) — no new harness.

- **`app/frontend/pages/Projects/Settings/SettingsPage.test.tsx`** — extend (existing delete specs
  at lines 94-100, 225-237):
  - with `project.canDelete = true`: the Delete button renders and clicking it opens the confirm
    modal / issues `router.delete` (existing behavior, now gated on the flag)
  - with `project.canDelete = false`: `screen.queryByRole('button', { name: 'Delete' })` is **not**
    in the document; Archive remains visible
  - **Update the shared test `project` fixture (`SettingsPage.test.tsx:9-25`) to include
    `canDelete: true`.** The existing delete specs (`:94-100` open-confirm-modal, `:225-237`
    issues-delete) click `getByRole('button', { name: 'Delete' })`; once the row is gated on
    `project.canDelete`, those specs will **break** (button absent) unless the fixture sets
    `canDelete: true`. This is a required fixture change, not optional.

### 7.5 Running (reference only — do not run as part of this design task)

Per repo conventions, Rails runs only in Docker: `docker compose exec -T web bin/rails test
test/policies/web/company/...`. Frontend: the project's Vitest runner (e.g. `npm run test` /
`vitest`) for the `.test.tsx` files.

## 8. Risks & Rollout

- **Behavioral risk — employees lose analytics/sessions access.** Intended by #211, but it is a
  user-visible change. Mitigated by also hiding the nav links (no dead links) and by the friendly
  alert on direct navigation. Communicate in release notes.
- **403-vs-302 mismatch — BLOCKING (DECISION 1, §5).** The issue's AC literally say "receives 403,"
  but the web layer returns 302+alert. The AC checkboxes and the denial tests are mutually
  contradictory until product picks 302-or-403, so **this must be resolved before any code or tests
  are written**, not flagged-and-deferred. Lowest-risk path: keep 302+alert, amend the AC wording
  from "403" to "denied (302 + not-authorized alert)". If product insists on literal 403, expect a
  broader change (all company policy failures) plus a regression sweep — see DECISION 1.
- **`new?`/`POST /company/sessions` non-route (OQ3).** Don't write a test for a route that 404s;
  confirm the AC line is dropped or retargeted.
- **Delete-button flag drift.** The FE `canDelete` duplicates the policy logic. Keep them in sync;
  the policy stays authoritative, so a drift only affects whether the (still-rejected) button is
  shown. Low severity.
- **Blast radius.** Three one-line policy edits, one controller prop addition, two FE files, plus
  tests. No schema/migration, no Typelizer regeneration, no service changes. Easy to revert by
  reverting the policy edits.
- **Rollout.** Single PR. No data backfill. No feature flag needed (pure authorization tightening).
  Deploy normally; verify with the new integration tests in CI.
