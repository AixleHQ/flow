# Technical Design — #213 Add view-only role (read analytics & workflows, no execution)

## 1. Problem & Goal

We need a **Viewer / client** capability: an external observer who can read a project's content (workflows, boards, assets) and its analytics, but can neither mutate anything (create/edit/delete workflows, boards, assets, agents, tools, integrations) nor execute anything (start a workflow run, launch an agent session). Read-only enforcement must be **server-side** (the source of truth) and **also reflected in the UI** (run/mutate controls hidden, not merely 403-ing on submit). A client must additionally be able to reach the app without going through the normal user machinery — most concretely, they must **skip onboarding's agent-configuration gate**, since the onboarding state machine currently hard-gates `step3 → step4` on `has_configured_agents?`.

### Product decision (settled — this reshapes the model)

The Viewer is a **GLOBAL "client" account type — an external observer, NOT a per-project membership role.** A client is read-only *everywhere* they can see, by virtue of *who they are*, not by virtue of a per-project membership tier. This decision supersedes the earlier "company-wide `users.role` vs per-project membership role" tension and the industry-precedent lean toward per-project roles in the research companion (`ai/research/technical-viewer-readonly-role-research-2026-07-01.md` §6.1) — those remain useful background on enforcement/UI patterns, but the *scope* question is now closed in favor of a global type.

Practically this means:

1. The client's read-only-ness is a property of the **user**, evaluated as a single predicate (`current_user.read_only?`), threaded into every write/execute decision.
2. A client still gains *visibility* into a project the normal way (they are added as a project collaborator, so `Project#accessible_by?` returns true), but their **role/type is global**, so they cannot write in *any* project.
3. A client is **exempt from normal user constraints** that assume an internal employee (onboarding agent setup, company email-domain matching, agent configuration). §2 produces a precise constraint map; §4 designs each bypass.

### Mechanism choice: global role value vs account-type flag vs STI

Three candidate mechanisms for the "global client type":

- **(A) Global role enum value** — add `viewer` to `enumerize :role, in: %i[employee admin super_admin]` on `app/models/user.rb:20`. `predicates: true` auto-generates `viewer?`. Zero schema change (`users.role` is already a non-null string column, `db/schema.rb:831`, indexed at `:843`). One-line reversible change; every existing role-aware code path (Ransack `%w[... role ...]` at `user.rb:57`, `ALLOWED_ROLES = User.role.values` at `members_controller.rb:48`) picks it up for free.
- **(B) Separate boolean account-type flag** — e.g. `users.client` boolean, default false. Requires a migration + backfill and a *second* dimension orthogonal to `role` (a client would still carry some `role` value, which is confusing — is a client an `employee`? an `admin`? neither is meaningful). It also duplicates the "what kind of account is this" question that `role` already answers.
- **(C) STI (`Viewer < User`)** — a subclass on the `users` table. The user raised this. **STI is NOT required** and is not recommended here.

**Recommendation: (A) — add `viewer` to the role enum, plus a domain predicate `User#read_only? = viewer?`.** Justification: it is the lightest mechanism consistent with the codebase, needs no migration, and `role` is already the single "what kind of account is this" axis. A separate boolean (B) adds a redundant second axis and a migration for no expressive gain. All the required behaviors (skip onboarding agent setup, cannot run, cannot mutate, exempt from domain matching) are ordinary conditionals keyed on one predicate — none of them need a distinct Ruby class.

**Why NOT STI (concise, decisive):** STI on the existing `users` table would require adding a `type` column (there is none today — `db/schema.rb:814-845` has no `type`) and a backfill setting `type = 'User'` for every existing row, i.e. a data migration touching the entire live users table with a NOT-NULL-ish invariant that all existing code must respect. It changes the class of `current_user` polymorphically, which ripples through `find_or_initialize_by(email:)` in `GoogleOmniAuthService` (`app/services/google_omni_auth_service.rb:24`), every `User.find`/scope, factories, and serializers — a broad blast radius on the app's most central model. STI buys you method overriding (`Viewer#can_complete_onboarding?` etc.), but the *exact same* "skip onboarding, cannot run" behavior is achievable with a single `read_only?` predicate and a handful of `if read_only?` branches — with far less risk. There is **no strong reason** found that requires per-subclass behavior (no divergent associations, no divergent validations that a guard clause can't express), so STI is rejected. If a future requirement demands wholly separate persistence/associations for clients, revisit then; it is out of scope for #213.

## 2. Current State (how it works today)

### Roles & users

- Roles: `enumerize :role, in: %i[employee admin super_admin], default: :employee, predicates: true, scope: true` (`app/models/user.rb:20`). `predicates: true` generates `employee?`, `admin?`, `super_admin?`; adding `viewer` generates `viewer?` automatically.
- `users.role` is a non-null string column with an index (`db/schema.rb:831`, `:843`). **No `type` column exists** (`db/schema.rb:814-845`) — relevant to the STI decision (§1).
- `company_id` is required unless `super_admin?` (`app/models/user.rb:42`; `super_admin_company_validation` at `:169-175`).
- `cannot_demote_last_admin` blocks demoting the final admin (`app/models/user.rb:184-194`) — only fires when `role_was == "admin"`, so unaffected by adding a viewer.

### The constraint map — everything an internal user must satisfy that a client must be EXEMPT from

This is the core of the product decision: a client is an *external observer*, so the constraints that assume "internal employee onboarding into their own company workspace" must not apply. Verified, with `path:line` and the exact bypass:

**(a) Onboarding — agent-configuration gate.**
- `UserStateMachine` onboarding aasm: `go_next` transition `step3 → step4` is `guard: :has_configured_agents?` (`app/state_machines/user_state_machine.rb:43`). An internal user cannot advance past step 3 without connecting an agent credential.
- `complete` transition `step4 → completed` is `guard: :can_complete_onboarding?` (`:52`), and `User#can_complete_onboarding?` requires `has_configured_agents?` (`app/models/user.rb:106-110`).
- `User#has_configured_agents?` === `agent_credentials.exists?` (`app/models/user.rb:86-88`).
- `enforce_onboarding` (`app/controllers/web/application_controller.rb:52-57`) redirects every signed-in, not-yet-`completed` user to `/onboarding`, so a client cannot skip onboarding by navigating around it — the state must actually reach `completed`.
- **Bypass:** branch the two guards on `read_only?` so a client never needs an agent credential (§4: `can_advance_to_authenticated?` + relaxed `can_complete_onboarding?`), and collapse the FE stepper for clients.

**(b) Email / company-domain matching on account creation.**
- `User` validation `validate :email_domain_matches_company, on: :create` (`app/models/user.rb:45`). The check (`:150-158`): if the user has a company and an email, and is not `super_admin?`, then `email.split("@").last` must equal `company.email_domain`, else it adds an error. **A client is an external party whose email domain will NOT match the company** — this validation would reject them.
- Self-service signup path: `GoogleOmniAuthService#find_or_create_user` (`app/services/google_omni_auth_service.rb:23-49`) does `User.find_or_initialize_by(email:)`, and for a new record resolves the company via `Company.find_by_email_domain(email)` (`:28`, model at `app/models/company.rb:68-71`) and forces `user.role = "employee"` (`:32`). This whole path assumes the person's email domain maps to a company — a client's would not (it would resolve `company = nil`, then fail `company_id` presence at `user.rb:42`), and even if it resolved it would stamp them `employee`, never `viewer`.
- Invitation path: `Web::Company::MembersController#create` (`app/controllers/web/company/members_controller.rb:16-26`) builds `current_company.users.new(...)` (so `company` is the inviter's company) and runs the same `email_domain_matches_company` on-create validation. Today it permits only `:email, :name` (`create_params`, `:51-53`) and reads role from `params.dig(:user, :role)` gated by `ALLOWED_ROLES = User.role.values` (`assign_role`, `:55-58`).
- **Bypass:** exempt clients from `email_domain_matches_company` (add `return if read_only?` to the guard, mirroring the existing `return if super_admin?`). Clients are created **only** via explicit admin invitation on the company Members screen (never via the domain-matched OAuth self-signup), with `role: "viewer"` — see §4. `company_id` stays required (a client still belongs to the company that invited them, which is correct and preserves tenant scoping).

**(c) Agent configuration and other client-inappropriate machinery.**
- `selected_agents` / `AVAILABLE_AGENTS` (`app/models/user.rb:17,44,160-167`) and `preferred_agent_language` (`:41`) exist to configure *how this user runs agents*. A client never runs agents. `selected_agents_valid` only fires when `selected_agents` is present (`:161`), so leaving it empty is fine — no bypass needed, but the onboarding FE should not ask a client to pick agents.
- Agent-session launch (`Api::V1::TerminalSessionsController#create`, `app/controllers/api/v1/terminal_sessions_controller.rb:13-27`, via `SessionService.create_and_start`) and workflow execution are the "run" surfaces a client must never reach — covered under enforcement (§2 API gap, §4).
- `default_agent_credential` (`app/models/user.rb:33,177-182`) is moot for a client (they have zero credentials).

Summary constraint map (each row: what an internal user must satisfy, where it lives, how a client is exempted):

| Constraint | Location | Client bypass |
|---|---|---|
| Must connect an agent to pass onboarding step3→step4 | `user_state_machine.rb:43` (`guard: :has_configured_agents?`) | Branch guard on `read_only?` → `can_advance_to_authenticated?` (§4) |
| Must have agents to complete onboarding | `user.rb:106-110` (`can_complete_onboarding?`) + `user_state_machine.rb:52` | Relax `can_complete_onboarding?`: `read_only? || has_configured_agents?` |
| Must reach `completed` before using app | `web/application_controller.rb:52-57` (`enforce_onboarding`) | No change to gate; the relaxed guards let a client *reach* `completed` |
| Email domain must match company domain (on create) | `user.rb:45,150-158` (`email_domain_matches_company`) | Add `return if read_only?` to the validation |
| Self-signup maps email→company & stamps `employee` | `google_omni_auth_service.rb:23-49`; `company.rb:68-71` | Clients are NOT self-signup; created only via admin invite with `role:"viewer"` |
| (Effectively) must configure agents to be useful | `user.rb:17,33,41,44` | Client onboarding FE skips agent-select/authenticate; empty `selected_agents` is valid |

### Pundit authorization (the dynamic dispatch scheme)

- `AuthorizationConcern` (`app/controllers/concerns/authorization_concern.rb`) turns a controller class into a policy authorization at request time. `init_authorize` (`:10-14`, run via `prepend_before_action`) defines a method named after the controller (e.g. `authorize_web_company_projects_workflows`) whose body calls `authorize(policy_method_params)`; `policy_method_params` maps the controller class to a symbol array like `[:web, :company, :projects, :workflows]` (`:36-41`), which Pundit resolves to `Web::Company::Projects::WorkflowsPolicy` and invokes the method named after the current action (`<action>?`). `dynamic_authorize!` (`:16-18`) actually *fires* it; `pundit_user` returns `policy_context` (`:20-22`).
- **The web tree fires it.** `Web::Company::ApplicationController` runs `before_action :dynamic_authorize!` (`app/controllers/web/company/application_controller.rb:10`) and sets `policy_context = BaseContext.new(current_user, params)` (`:28-30`).
- `Web::Company::Projects::ApplicationController` overrides `policy_context = ProjectContext.new(current_user, params, project: current_project)` (project loaded via `Project.for_user(current_user)…find(params[:project_id])`).
- **Every project policy today is uniform**: each action delegates to `project_accessible? = project&.accessible_by?(current_user)`. There is currently no "read but don't write" tier — any collaborator can do everything except a handful of owner/admin-gated actions (e.g. `BoardsPolicy` create/update/destroy are owner-only; `RepositoriesPolicy`/`IntegrationsPolicy` writes require admin/owner).

### THE ENFORCEMENT GAP — the API tree is Pundit-*capable* but never Pundit-*gated* (verified)

This is the finding #213 must close, verified against the source:

- `Api::V1::ApplicationController` (`app/controllers/api/v1/application_controller.rb`) **does** `include Pundit::Authorization` (`:7`), `include AuthorizationConcern` (`:8`), defines `policy_context = BaseContext.new(current_user, params)` (`:22-24`), and has `rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized` returning a JSON 403 (`:17`, `:26-28`).
- **BUT it never adds `before_action :dynamic_authorize!`** — its only `before_action` is `authenticate_user!` (`:15`). Contrast the web base controller, which DOES call it (`web/company/application_controller.rb:10`).
- `Api::V1::Projects::ApplicationController` (`app/controllers/api/v1/projects/application_controller.rb:6-14`) sets a `ProjectContext` policy_context (`:11-13`) and loads `current_project` via `Project.for_user(current_user).find(params[:project_id])` (`:7-9`) — **but calls no authorization**. No API controller calls `authorize` manually either.
- **Net effect:** every `Api::V1::Projects::*` endpoint is gated ONLY by `authenticate_user!` + the `Project.for_user(current_user)` scoping in `current_project` (a member/not-member check). There is **NO per-action read-vs-write policy**. A user who is *any* collaborator on a project passes `Project.for_user` and can therefore hit every mutating endpoint in the subtree.

The frontend posts its real mutations to exactly this un-gated tree (routes `config/routes.rb:60-120`):
- **Board task CRUD + execution** — `Board::TasksController` `create`/`update`/`destroy`/`move`/`trigger_workflow` (`routes.rb:103-108`). `trigger_workflow` is the board's workflow-execution path. There are **no** web controllers under `app/controllers/web/company/projects/board/`, so editing the WEB `Board::TasksPolicy` blocks nothing.
- **Asset upload/delete** — `Api::V1::Projects::AssetsController` `create`/`destroy` (`routes.rb:62`). The WEB assets controller is index-only, so the WEB `AssetsPolicy#create?/destroy?` is dead code for the real path. Board-task assets are also API-only (`routes.rb:111`).
- **Board columns / bindings** — `Board::ColumnsController` (full CRUD + `reorder`, `:94-101`), `Columns::WorkflowBindingsController` (`:99`), `board#create/update/destroy` (`:91`).
- **Task comments / gates** — `Board::Task::CommentsController#create` (`:110`), `Board::Task::GatesController#destroy` (`:112`).
- **Workflows + steps + triggers** — `WorkflowsController#update/destroy` (`:68`), `Workflows::StepsController` (create/update/destroy/`reorder`, `:70-74`), `Workflows::TriggersController` (create/update/destroy, `:75`).
- **Workflow run assets** — `WorkflowRunAssetsController` `export`/`export_all` (`:82,86`) (both POST) and `download`/`index` (GET reads).
- **Terminal sessions (agent launch)** — `Api::V1::TerminalSessionsController#create` (`app/controllers/api/v1/terminal_sessions_controller.rb:13-27`). Note it inherits `Api::V1::ApplicationController` **directly** (not the `Projects` subtree), guarded only by `current_user.company.projects.find` + `current_user.terminal_sessions.build` scoping (`:14`, via `SessionService`).

### Onboarding (FE)

- `Web::OnboardingController#update` (`app/controllers/web/onboarding_controller.rb:23-29`) just calls `current_user.update(onboarding_params)`; `onboarding_state_event` is permitted (`:37-43`) and applied via the state machine.
- **Silent no-op semantics (affects tests):** `StateEventConcern` defines `onboarding_state_event=` to fire the event ONLY `if machine.may_fire_event?` (`app/state_machines/concerns/state_event_concern.rb:22-31`). If the guard fails, the event is silently swallowed — no error, no state change — and the controller still redirects with success. Assert by STATE, not HTTP status.
- Frontend `OnboardingPage.tsx`: a 4-step `Stepper` (`:566-571`); step2 = "Select Agents", step3 = "Authenticate" (launches auth sessions via `Api::V1::TerminalSessionsController#create`).

### Types & frontend permission plumbing

- Generated types (Typelizer, do-not-edit): `CurrentUser.ts`/`User.ts` type `role: string`. Hand-maintained `UserRole = 'employee' | 'admin' | 'super_admin'` union in `app/frontend/shared/ui/types.ts:2`.
- `inertia_share` exposes company-level `permissions: { is_admin, can_manage_members, can_manage_projects }` (all `current_user.admin?`) from `Web::Company::ApplicationController:14-24`. **No project-scoped capability flag is shared today.**
- `Record<UserRole, …>` literals exist in `app/frontend/shared/resources/members/MembersContent.tsx` (`ROLE_COLORS`/`ROLE_LABELS`) and `app/frontend/pages/Profile/Show.tsx` — extending `UserRole` without adding a `viewer` key breaks `tsc` and yields blank badges at runtime.

### Tests

- Minitest. **No policy unit tests exist.** Controller/integration tests under `test/integration/web/...` and `test/controllers/api/...`. Factories: `test/factories/users.rb` (role traits, `:onboarding_completed`, `:with_agent_credential`), `test/factories/project_collaborators.rb`. Frontend: Vitest + jsdom, co-located `*.test.tsx`, mocking `@inertiajs/react`.

## 3. Proposed Design (approach + rationale)

### Approach: a global `viewer` (client) role, a single `read_only?` predicate threaded through both the web Pundit policies AND a new API guard, plus constraint exemptions and a UI capability flag

1. **Model (global client type).** Add `viewer` to the role enum and a domain predicate `User#read_only? = viewer?` (§1 mechanism A). Keep `company_id` required (a client belongs to the inviting company — preserves tenant scoping and reuses `accessible_by?` for reads). Add the onboarding-exemption helpers and the domain-matching exemption (constraint map (a),(b)). No migration.

2. **Constraint exemptions (the "external observer" part).** Relax the onboarding guards for clients and exempt clients from `email_domain_matches_company` (§4 (a),(b)). Clients are created only by explicit admin invite with `role: "viewer"`, never via domain-matched OAuth self-signup.

3. **Web Pundit: one shared write gate.** Add `project_writable? = project_accessible? && !current_user.read_only?` on the shared base policy and switch *write/execute* actions to it, leaving *reads* on `project_accessible?`. This mirrors the existing one-liner policy idiom (e.g. `RepositoriesPolicy#create? = project_accessible? && current_user.admin?`) and is the source of truth for every web-dispatched action.

4. **FULL API authorization (product-settled — the biggest correctness gap).** Rather than the earlier phased "verb-backstop-now, Punditize-later," #213 now brings the entire `api/v1` tree under per-action Pundit authorization by default:
   - **Enable `before_action :dynamic_authorize!` on the WHOLE `Api::V1::ApplicationController`** (not just the `Projects` subtree), so every current *and future* API action is policy-checked by default ("so we don't lose it later"). The plumbing (`Pundit::Authorization`, `AuthorizationConcern`, `policy_context`, `rescue_from Pundit::NotAuthorizedError`) is already present on this base — only the trigger `before_action` is missing.
   - **Author a Pundit policy class under the `Api::` namespace for EVERY user-facing api/v1 controller**, mirroring the parallel `Web::Company::*` policy where one exists (e.g. `Api::V1::Projects::Board::TasksPolicy` mirrors `Web::Company::Projects::Board::TasksPolicy`). Reads (index/show/GET-y custom actions) → `project_accessible?` (allowed for members incl. clients); writes (create/update/destroy/move/trigger_workflow/reorder/export/…) → `project_writable?` (denied for `read_only?` clients). Full mapping table in §4.
   - **Fail-closed on missing policies:** add `rescue_from Pundit::NotDefinedError` → 403 to the API base so a controller that ever lacks a policy denies rather than 500s (§4).
   - **Tripwire:** add `after_action :verify_authorized` (test env, optionally dev) so any API action that never called `authorize` fails the suite — the mechanism that keeps coverage from regressing (§4).
   - **Exclude the service-to-service `Api::V1::Internal::*` controllers** (`usage_statistics`, `ws_auth`) from user Pundit — they use non-user auth and get `skip_before_action :dynamic_authorize!` + `skip_after_action :verify_authorized` (§4 Internal-namespace decision).
   - **Keep a global read-only `deny_read_only_mutation!` verb backstop** as defense-in-depth on top of the per-action policies (§4).
   - **`Api::V1::TerminalSessionsController#create`** additionally gets an explicit 403 for `read_only?` clients (the agent-launch block), on top of its policy.

5. **UI capability flag (UX only, never the boundary).** Share a project-scoped `can` object (`{ canExecute, canManage }`) through Inertia props and hide run/mutate controls from it. Server authorization is the boundary; this is purely to avoid a client clicking a button that 403s.

6. **Onboarding bypass for the client type (§4 (a)).** Relaxed state-machine guards + a collapsed FE stepper (Profile → Complete) for clients.

### Why this design

- **Server-side is the source of truth** via per-action Pundit policies on BOTH the web tree (`project_writable?`) and the full api/v1 tree (`dynamic_authorize!` + `Api::` policies), backed by a `deny_read_only_mutation!` verb backstop and a `verify_authorized` tripwire. Nothing relies on the UI.
- **Authorize-by-default, fail-closed.** Turning `dynamic_authorize!` on at the API root + `rescue_from Pundit::NotDefinedError` + `after_action :verify_authorized` means a *new* API controller shipped without a policy either 403s in prod or fails the test suite — the gap that existed for the whole `Api::V1::Projects::*` tree can't silently recur.
- **Global client type = one predicate.** `read_only?` is evaluated identically in every policy's `project_writable?`, in the verb backstop, in the terminal-sessions guard, and in the onboarding/domain exemptions — no per-project membership plumbing, no new join-table column, no STI.
- **Lowest-risk footprint on the model:** an additive enum value (no migration), guard-clause exemptions, one shared policy predicate. STI's whole-table `type` migration and polymorphic ripple are avoided (§1). The API-authorization work is the deliberate, larger cost of doing enforcement right (see Risks/Rollout §8).

## 4. Detailed Changes

### Backend

#### `app/models/user.rb`
- Line 20: add `viewer` to the enum (`predicates: true` auto-generates `viewer?`):
  ```ruby
  enumerize :role, in: %i[employee admin super_admin viewer], default: :employee, predicates: true, scope: true
  ```
- Add the client predicate + onboarding helpers (near `onboarding_completed?`):
  ```ruby
  # A "client" (external observer) account: read-only everywhere, cannot run/mutate.
  def read_only?
    viewer?
  end

  # Clients never connect/run an agent, so onboarding must not require one.
  def onboarding_requires_agent?
    !read_only?
  end

  def can_advance_to_authenticated?
    onboarding_requires_agent? ? has_configured_agents? : true
  end
  ```
- Relax `can_complete_onboarding?` (`:106-110`) so clients don't need agents:
  ```ruby
  def can_complete_onboarding?
    position.present? &&
      preferred_agent_language.present? &&
      (read_only? || has_configured_agents?)
  end
  ```
- **Constraint (b) — exempt clients from company-domain matching.** Edit `email_domain_matches_company` (`:150-158`) to short-circuit for clients, mirroring the existing `super_admin?` exemption:
  ```ruby
  def email_domain_matches_company
    return if company.blank? || email.blank?
    return if super_admin?
    return if read_only? # external clients have their own email domain

    domain = email.split("@").last
    return if domain == company.email_domain

    errors.add(:email, "domain must match company domain (#{company.email_domain})")
  end
  ```
- `cannot_demote_last_admin` (`:184-194`) is unaffected (fires only when `role_was == "admin"`). `company_id` presence (`:42`) still applies to clients (correct — they belong to the inviting company).

#### `app/state_machines/user_state_machine.rb`
- Change the `step3 → step4` transition guard (`:43`) from `:has_configured_agents?` to `:can_advance_to_authenticated?`:
  ```ruby
  event :go_next do
    transitions from: :step1, to: :step2
    transitions from: :step2, to: :step3
    transitions from: :step3, to: :step4, guard: :can_advance_to_authenticated?
  end
  ```
  (Helper defined on `User`, above.) Keep the linear states; a client passes `go_next` freely and the FE collapses the visible steps (no new states — see OPEN QUESTION 2).

#### `app/controllers/web/company/members_controller.rb` (client creation)
- `ALLOWED_ROLES = User.role.values.freeze` (`:48`) automatically includes `viewer` once the enum is extended — **no code change**; `assign_role` (`:55-58`) accepts `"viewer"` since it checks `ALLOWED_ROLES.include?(role)`. This is the intended client-creation path (explicit admin invite), and the domain-matching exemption above lets an external-domain email save. No other change here.

#### Web Pundit: shared write gate
Extend `Web::Company::ApplicationPolicy` (`app/policies/web/company/application_policy.rb`), the base all project policies subclass. Today it defines only `current_user`; **add** `project`, `project_accessible?`, `project_writable?` (lifting the per-policy duplicates up):
```ruby
def current_user       = context.user
def project            = context.project
def project_accessible? = project&.accessible_by?(current_user)
def project_writable?  = project_accessible? && !current_user.read_only?
```
> Company-level policies (`MembersPolicy`, `AssetsPolicy`, `AnalyticsPolicy`, `SessionsPolicy`, `ProjectsPolicy`, …) resolve their bare `ApplicationPolicy` superclass to this `Web::Company::ApplicationPolicy` and inherit the new methods harmlessly (their `context` is a `BaseContext` with no `project`, and they never call these methods — they gate on `admin?`).

Then switch write/execute actions to `project_writable?` and drop each subclass's now-duplicated private `project`/`project_accessible?`:
- `workflows_policy.rb`: reads (`index?`/`show?`/`builder?`) → `project_accessible?`; `create?`/`update?`/`destroy?`/`publish?`/`unpublish?`/`duplicate?` → `project_writable?`.
- `workflow_runs_policy.rb`: `index?`/`show?` → `project_accessible?`; `create?`/`cancel?`/`approve_step?`/`retry_step?`/`skip_step?` → `project_writable?` (the workflow-execution AC).
- `sessions_policy.rb`: `index?`/`show?` → `project_accessible?`; `new?` → `project_writable?`. **Caveat:** `new?` only gates the web launch-form render; the real launch is the API POST (§4 API). This is UX, not the AC block.
- `boards_policy.rb`: `show?` → `project_accessible?`; create/update/destroy already owner-only (leave — a client can't own).
- `board/tasks_policy.rb` and the `board/task/*` mirrors: set `create?`/`update?`/`destroy?`/`move?`/`trigger_workflow?` → `project_writable?`. These WEB policies are still not dispatched (board tasks are API-served), but they now also serve as the **classification source of truth the parallel `Api::V1::Projects::Board::*` policies mirror/inherit** (§4 API mapping), so keep them correct.
- `assets_policy.rb`: `index?`/`versions?`/`download?` → `project_accessible?`; `create?`/`destroy?` → `project_writable?`. Web asset writes are still API-served, but this is the mirror for `Api::V1::Projects::AssetsPolicy`.
- `members_policy.rb`: today `create?`/`destroy?` are `project_accessible?` — so a client collaborator could add/remove collaborators. Change both → `project_writable?`; `index?` stays `project_accessible?`. **This controller IS web-dispatched, so this edit is effective.** (Overlaps ticket #211.)
- `analytics_policy.rb`: `index?` → `project_accessible?` (clients read analytics — AC).
- `agents_policy.rb`/`tools_policy.rb`/`mcp_servers_policy.rb`/`skills_policy.rb`: reads → `project_accessible?`; writes → `project_writable?`.
- `integrations_policy.rb`/`repositories_policy.rb`: reads → `project_accessible?`; writes already require admin/owner (a client is never admin/owner — safe; optionally add `&& !current_user.read_only?` defensively).
- `aixle_builder_policy.rb`: `show?`/`show_session?` → `project_accessible?`; **`start?`/`finish?` → `project_writable?`** (Aixle Builder runs agents; these ARE web-dispatched, so effective).
- Audit the remaining project policies (`overview`, `settings`, `config_items`, `workflows/steps`, `workflow_run_assets`, `sessions/artifacts`, `board/columns`, `board/view_presets`, `board/activities`): reads → `project_accessible?`, mutations → `project_writable?`.

#### API authorization — the full design

##### `app/controllers/api/v1/application_controller.rb` (authorize-by-default root)
Turn on dynamic authorization for the whole tree, fail closed on a missing policy, and add the tripwire:
```ruby
class ApplicationController < ::ApplicationController
  include Pundit::Authorization
  include AuthorizationConcern
  # …existing…
  before_action :authenticate_user!
  before_action :dynamic_authorize!            # NEW: every action is policy-checked by default
  after_action  :verify_authorized, unless: :devise_or_skipped?  # NEW tripwire (see note)

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from Pundit::NotDefinedError,    with: :user_not_authorized  # NEW: missing policy ⇒ 403, not 500
  # …
end
```
- **How `dynamic_authorize!` maps controller#action → policy:** `AuthorizationConcern#dynamic_authorize!` (`authorization_concern.rb:16-18`) calls the per-controller method defined by `init_authorize` (`:10-14`), whose body is `authorize(policy_method_params)`; `policy_method_params` (`:36-41`) converts e.g. `Api::V1::Projects::Board::TasksController` → `[:api, :v1, :projects, :board, :tasks]`, which Pundit resolves to `Api::V1::Projects::Board::TasksPolicy`, calling `<action>?`. Because `init_authorize` guards on `self.class.ancestors.include?(ApplicationController)` (`:11`), it is a no-op for a controller that isn't in this tree — safe.
- **`Pundit::NotDefinedError` handling (documented choice):** we do BOTH — (1) author a policy for every user-facing controller so the error should never fire in practice, AND (2) add `rescue_from Pundit::NotDefinedError, with: :user_not_authorized` so that if a *future* controller ships without a policy, it fails **closed** (403) instead of 500ing. Belt and suspenders; (2) is cheap insurance and turns "forgot a policy" from an outage into a deny.
- **`verify_authorized` tripwire:** Pundit's `after_action :verify_authorized` raises if `authorize` was never called in an action. Because `dynamic_authorize!` is a `before_action` that always calls `authorize`, this normally passes — its value is catching a controller that *skipped* `dynamic_authorize!` without also being deliberately excluded. Recommend enabling it in **test** (so the suite fails on any unauthorized API action — the anti-regression mechanism) and optionally **dev**; keep it off or rescued in production to avoid turning a coverage bug into a 500 (the `NotDefinedError` rescue already covers prod fail-closed). `devise_or_skipped?` here is shorthand for "skip on the excluded Internal controllers" — implement via `skip_after_action :verify_authorized` on those (below) rather than a predicate if simpler.
- **Verb backstop (defense-in-depth, kept):** in addition to per-action policies, add a global read-only mutation guard on this base so a `read_only?` client can never mutate even if a policy is mis-classified:
  ```ruby
  before_action :deny_read_only_mutation!
  # Clients (read_only?) may issue safe (GET/HEAD) requests only.
  def deny_read_only_mutation!
    return unless current_user&.read_only?
    return if request.get? || request.head?
    render json: { error: "Not authorized" }, status: :forbidden
  end
  ```
  All mutating api/v1 routes are POST/PATCH/PUT/DELETE and all GET routes are genuine reads (verified against `config/routes.rb`), so verb ≈ intent here. The JSON 403 matches the existing `user_not_authorized` shape (`api/v1/application_controller.rb:26-28`).

##### Excluded from user Pundit: `Api::V1::Internal::*` (service-to-service) — investigated

Both Internal controllers **skip user authentication** and authenticate by other means, so they must NOT be given user-based policies and must be excluded from `dynamic_authorize!`/`verify_authorized`:
- `Api::V1::Internal::UsageStatisticsController` (`app/controllers/api/v1/internal/usage_statistics_controller.rb`) — `skip_before_action :authenticate_user!` (`:7`); `#create` (POST `/api/v1/internal/usage_statistics`, `routes.rb:43`) hands the **raw request body** to `UsageStatisticsService.process(request.raw_post)`. There is no `current_user`; it is an internal ingest endpoint (agent runtimes posting usage). A user policy is meaningless here.
- `Api::V1::Internal::WsAuthController` (`app/controllers/api/v1/internal/ws_auth_controller.rb`) — `skip_before_action :authenticate_user!` (`:31`); `#show` (GET `/api/v1/internal/ws_auth`, `routes.rb:42`) is a **Traefik ForwardAuth** endpoint that authenticates via the session cookie forwarded by Traefik and authorizes by checking `terminal_session.user_id == current_user.id` and session state **inline** (`:44-63`), returning bare `head :ok/:unauthorized/:forbidden/:not_found`. It performs its own object-level authorization by hand; wrapping it in Pundit would be redundant and would break the ForwardAuth contract.
- **Decision:** give the Internal namespace its own exclusion. Cleanest: an `Api::V1::Internal::ApplicationController < Api::V1::ApplicationController` that does `skip_before_action :dynamic_authorize!` and `skip_after_action :verify_authorized` (and keeps the existing `skip_before_action :authenticate_user!`), and reparent both Internal controllers to it. If a dedicated base is undesirable, put the two `skip_*` lines directly on each Internal controller. Either way they are **out of scope for user Pundit**. (The verb backstop `deny_read_only_mutation!` no-ops here too, since it early-returns when `current_user` is nil.)

##### Top-level asset controllers — investigated

- `Api::V1::AssetsController` (`app/controllers/api/v1/assets_controller.rb`) — nested in `module Api; module V1`, so its `class AssetsController < ApplicationController` (`:5`) resolves to **`Api::V1::ApplicationController`** (nearest enclosing constant), i.e. it DOES inherit the API base and its Pundit machinery. Actions `presign`/`upload` (GET/POST, `routes.rb:36-37`) generate a presigned URL and accept a direct upload to *cache* (temp) storage — not yet attached to any project/company resource. **In scope for user Pundit:** add `Api::V1::AssetsPolicy` with `presign?`/`upload?`. Since caching an upload is a precursor to a *write*, and a client should never upload, classify both as **write → `!read_only?`** (there is no project context here; gate on `current_user` being a non-client, i.e. `!user.read_only?`). Alternatively, if product wants clients to never even reach the uploader, this is also enforced by the FE hiding upload controls — but the policy is the boundary.
- `Api::V1::Company::AssetsController` (`app/controllers/api/v1/company/assets_controller.rb`) — `< Api::V1::ApplicationController` (`:6`); `create`/`destroy` write company assets, `download` reads one. **In scope:** add `Api::V1::Company::AssetsPolicy` — `download?` read → allowed for company members (incl. clients); `create?`/`destroy?` write → `!read_only?` (and note these operate on `current_user.company` scope, so a company-scoped `writable?` = `!read_only?` is the gate; owner/admin gating is a separate #211 concern).

##### `app/controllers/api/v1/projects/application_controller.rb`
The `ProjectContext` + `current_project` here stay as-is; `dynamic_authorize!`/`deny_read_only_mutation!` are now inherited from the API root, so no per-subtree `before_action` is needed (remove the earlier plan to add them only here). Keep:
```ruby
def current_project
  @current_project ||= Project.for_user(current_user).find(params[:project_id])
end
def policy_context
  ProjectContext.new(current_user, params, project: current_project)
end
```

##### Controller → policy mapping (every user-facing api/v1 controller)

Read = allowed for any project/company member including clients (`project_accessible?`, or company-membership for company/top-level scopes). Write = denied for `read_only?` clients (`project_writable? = project_accessible? && !read_only?`; for non-project scopes, `!read_only?`). "Mirrors" = the parallel `Web::Company::*` policy to copy classification from.

| Controller | Policy to add (`Api::` ns) | Mirrors (`Web::Company::…`) | Actions → R/W |
|---|---|---|---|
| `Api::V1::AssetsController` | `Api::V1::AssetsPolicy` | — (no web mirror) | `presign?` **W**, `upload?` **W** |
| `Api::V1::Company::AssetsController` | `Api::V1::Company::AssetsPolicy` | `Web::Company::AssetsPolicy` | `download?` **R**; `create?` **W**, `destroy?` **W** |
| `Api::V1::TerminalSessionsController` | `Api::V1::TerminalSessionsPolicy` | — (no web mirror; web `SessionsPolicy` is project-scoped) | `show?` **R**; `create?` **W**, `destroy?` **W**, `finish?` **W** |
| `Api::V1::Projects::AssetsController` | `Api::V1::Projects::AssetsPolicy` | `…::Projects::AssetsPolicy` | `download?` **R**; `create?` **W**, `destroy?` **W** |
| `Api::V1::Projects::BoardController` | `Api::V1::Projects::BoardPolicy` | `…::Projects::BoardsPolicy` | `create?`/`update?`/`destroy?`/`create_from_preset?` all **W** |
| `Api::V1::Projects::Board::ActivitiesController` | `Api::V1::Projects::Board::ActivitiesPolicy` | `…::Board::ActivitiesPolicy` | `index?` **R** |
| `Api::V1::Projects::Board::ColumnsController` | `Api::V1::Projects::Board::ColumnsPolicy` | `…::Board::ColumnsPolicy` | `index?`/`show?` **R**; `create?`/`update?`/`destroy?`/`reorder?` **W** |
| `Api::V1::Projects::Board::Columns::WorkflowBindingsController` | `Api::V1::Projects::Board::Columns::WorkflowBindingPolicy` | — (no direct web mirror) | `show?` **R**; `create?`/`update?`/`destroy?` **W** |
| `Api::V1::Projects::Board::TasksController` | `Api::V1::Projects::Board::TasksPolicy` | `…::Board::TasksPolicy` | `index?`/`show?`/`workflow_runs?` **R**; `create?`/`update?`/`destroy?`/`move?`/`trigger_workflow?` **W** |
| `Api::V1::Projects::Board::ViewPresetsController` | `Api::V1::Projects::Board::ViewPresetsPolicy` | `…::Board::ViewPresetsPolicy` | `index?` **R**; `create?`/`destroy?` **W** |
| `Api::V1::Projects::Board::Task::ActivitiesController` | `…::Board::Task::ActivitiesPolicy` | `…::Board::Task::ActivitiesPolicy` | `index?` **R** |
| `Api::V1::Projects::Board::Task::AssetsController` | `…::Board::Task::AssetsPolicy` | `…::Board::Task::AssetsPolicy` | `index?` **R**; `create?`/`destroy?` **W** |
| `Api::V1::Projects::Board::Task::CommentsController` | `…::Board::Task::CommentsPolicy` | `…::Board::Task::CommentsPolicy` | `index?` **R**; `create?` **W** |
| `Api::V1::Projects::Board::Task::GatesController` | `…::Board::Task::GatesPolicy` | — (web has `waits_policy`, closest) | `destroy?` **W** |
| `Api::V1::Projects::Board::Task::StatisticsController` | `…::Board::Task::StatisticsPolicy` | `…::Board::Task::StatisticsPolicy` | `show?` **R** |
| `Api::V1::Projects::Board::Task::TransitionsController` | `…::Board::Task::TransitionsPolicy` | `…::Board::Task::TransitionsPolicy` | `index?` **R** |
| `Api::V1::Projects::WorkflowRunAssetsController` | `Api::V1::Projects::WorkflowRunAssetsPolicy` | `…::Projects::WorkflowRunAssetsPolicy` | `index?`/`download?` **R**; `export?`/`export_all?` **W** (POST side-effects) |
| `Api::V1::Projects::WorkflowsController` | `Api::V1::Projects::WorkflowsPolicy` | `…::Projects::WorkflowsPolicy` | `show?` **R**; `update?`/`destroy?` **W** |
| `Api::V1::Projects::Workflows::StepsController` | `Api::V1::Projects::Workflows::StepsPolicy` | `…::Projects::Workflows::StepsPolicy` | `index?`/`show?` **R**; `create?`/`update?`/`destroy?`/`reorder?` **W** |
| `Api::V1::Projects::Workflows::TriggersController` | `Api::V1::Projects::Workflows::TriggersPolicy` | — (no direct web mirror) | `index?` **R**; `create?`/`update?`/`destroy?` **W** |
| `Api::V1::Internal::UsageStatisticsController` | **EXCLUDED** — service auth (raw body) | — | skip `dynamic_authorize!`/`verify_authorized` |
| `Api::V1::Internal::WsAuthController` | **EXCLUDED** — Traefik ForwardAuth, inline authz | — | skip `dynamic_authorize!`/`verify_authorized` |

Base/abstract controllers with no actions (`Api::V1::Projects::ApplicationController`, `…::Board::ApplicationController`, `…::Board::Task::ApplicationController`, `…::Workflows::ApplicationController`) need no policy — they route no actions, and `dynamic_authorize!` only fires on concrete actions. Notes:
- `export?`/`export_all?` on `WorkflowRunAssetsController` are POST and produce artifacts, so classified **W** even though "export" sounds read-ish — a client shouldn't trigger them. `download?`/`index?` are GET reads.
- Where a `ProjectContext` isn't available (`Api::V1::AssetsController`, `…::Company::AssetsController`, `TerminalSessionsController`), the policy gates on `context.user.read_only?` directly instead of `project_writable?`. Give these an `Api::` base policy exposing `user`/`read_only?` helpers, or reuse `ApplicationPolicy#user` (`app/policies/application_policy.rb:11-13`) and add `read_only?`.
- Implementation shortcut to avoid duplicating logic: the `Api::V1::Projects::*` policies can `< Web::Company::Projects::XxxPolicy` (they share the `ProjectContext` shape and `project_accessible?`/`project_writable?` from the web base), overriding only where action names differ. Verify Pundit resolves the `Api::` constant name (it does — the class just needs to exist at `Api::V1::Projects::…Policy`); inheriting the web implementation keeps read/write classification in one place. Decide per-policy whether to inherit or copy.

##### `app/controllers/api/v1/terminal_sessions_controller.rb` (agent-launch: policy + explicit guard)
`class TerminalSessionsController < ApplicationController` here also resolves to `Api::V1::ApplicationController` (nested in `module Api; module V1`), so it inherits `dynamic_authorize!` and will require `Api::V1::TerminalSessionsPolicy` (table above). On top of the policy, keep an explicit `#create` guard for clarity of the agent-launch block:
```ruby
def create
  if current_user.read_only? && session_params[:session_type] != "auth_setup"
    return render json: { error: "Viewers cannot launch sessions" }, status: :forbidden
  end
  # …existing body…
end
```
(`session_params` permits `:session_type` — `:50-58`. The FE's camelCase `sessionType` is deep-underscored to `session_type` by `ApplicationController#underscore_params` before the controller runs, so the snake_case key match is correct.) `auth_setup` is exempted because a client never reaches onboarding's auth step; if product prefers, block *all* creates for clients. Note the existing `skip_before_action :authenticate_user!, only: []` (`:6`) has an **empty `only:`** and is therefore a no-op — auth stays enabled, so `current_user` is present.

#### Project capability sharing for the UI (`inertia_share`)
In `app/controllers/web/company/projects/application_controller.rb`, mirror the company-level `permissions` share:
```ruby
inertia_share do
  {
    projectPermissions: InertiaRails.always {
      {
        can_execute: !current_user.read_only?,
        can_manage: current_user.admin? || current_project.admin?(current_user)
      }
    }
  }
end
```

### Frontend

> Typelizer-generated types (`app/frontend/types/generated/*`) are never hand-edited; the hand-maintained union must change.

#### `app/frontend/shared/ui/types.ts`
- Extend the union (`:2`): `export type UserRole = 'employee' | 'admin' | 'super_admin' | 'viewer';`
- Add `export interface ProjectPermissions { canExecute: boolean; canManage: boolean; }` and thread into shared props (or read per-page from `usePage().props.projectPermissions`).

#### `Record<UserRole, …>` breaks (REQUIRED — tsc + runtime)
- `app/frontend/shared/resources/members/MembersContent.tsx`: add a `viewer` entry to `ROLE_COLORS` and `ROLE_LABELS` (e.g. `viewer: 'teal'`, `viewer: 'Viewer'`); add `{ value: 'viewer', label: 'Viewer' }` to `ROLE_FILTER_OPTIONS`; extend the role-toggle menu with a "Make Viewer" affordance (keep the last-admin guard).
- `app/frontend/pages/Profile/Show.tsx`: add `viewer` entries to its `ROLE_COLORS`/`ROLE_LABELS` (overlaps ticket #303 — coordinate).

#### `app/frontend/shared/resources/members/InviteUserModal.tsx`
- Add `{ value: 'viewer', label: 'Viewer' }` to `ROLE_OPTIONS` so admins can invite clients at the company level.

#### `app/frontend/pages/Onboarding/OnboardingPage.tsx` (client onboarding bypass)
- Read `const isViewer = currentUser?.role === 'viewer';`.
- When `isViewer`: render a reduced `Stepper` (Profile → Complete), hiding "Select Agents" and "Authenticate"; branch `STEP_PROGRESS`/`stateToStep`; in `handleNext`, after validating position+language, drive the relaxed state machine straight toward `completed`; drop the `selectedAgents` requirement (`canAdvanceStep2`).
- Keep the non-client flow byte-for-byte unchanged.

#### Project pages — hide run/mutate controls (gate on `projectPermissions.canExecute` / `canManage`)
- `Projects/Workflows/WorkflowsPage.tsx`: hide "Run", "New Workflow", edit/delete/publish, `RunWorkflowModal`; keep Configure/Run History/Catalog reads.
- `shared/components/SessionNewForm.tsx` + `Projects/Sessions/SessionsPage.tsx`: hide/disable "Start Session" / "New Session".
- `Projects/WorkflowRuns/ShowPage.tsx`: hide cancel/approve/retry/skip.
- `Projects/Board/BoardPage.tsx`: hide task create/move/edit + "trigger workflow".
- `Projects/Assets/AssetsPage.tsx` (+ `shared/resources/assets/AssetsContent.tsx`): hide upload/delete.
- `Projects/Agents|Tools|McpServers|Skills|Integrations|Repositories/*Page.tsx`: hide create/edit/delete.
- `Projects/AixleBuilder/LandingPage.tsx`: hide "start build".

#### Type regeneration
- `role` is already serialized as `string`, so no serializer change is required. If any computed attribute is added, annotate with `typelize` and regenerate (container): `docker compose exec -T web bundle exec rails runner "Typelizer::Generator.call(force: true)"`.

### Data migration
- **None required.** `users.role` is already a `string` column (`db/schema.rb:831`); adding an enum value does not touch the column. No `type` column, no backfill (that would only be needed for STI, which is rejected — §1).

## 5. Edge Cases & Decisions

- **DECISION:** The Viewer is a **global client account type** (`users.role = "viewer"`), not a per-project membership role and not an STI subclass. Read-only-ness is the single predicate `read_only?`.
- **DECISION (STI rejected):** No `Viewer < User` STI. Rationale in §1 — no `type` column today, whole-table backfill + polymorphic ripple on the central model, and every needed behavior is a guard clause on `read_only?`.
- **DECISION (constraint exemptions):** Clients are exempt from (a) the onboarding agent gate and (b) company email-domain matching, and are created only via explicit admin invite (not domain-matched OAuth self-signup). See the §2 constraint map.
- **DECISION:** Reads stay `project_accessible?`; writes/execution → `project_writable? = project_accessible? && !read_only?`.
- **DECISION (FULL API authorization — product-settled):** enable `before_action :dynamic_authorize!` on the whole `Api::V1::ApplicationController` (authorize-by-default), author an `Api::`-namespace policy for every user-facing api/v1 controller (mapping table in §4), `rescue_from Pundit::NotDefinedError` → 403 (fail-closed on a missing policy), add `after_action :verify_authorized` as a test-env tripwire, keep the `deny_read_only_mutation!` verb backstop as defense-in-depth, and explicitly 403 clients in `Api::V1::TerminalSessionsController#create`. This — not the web `Board::TasksPolicy`/`AssetsPolicy` edits — is what actually blocks board task CRUD/`trigger_workflow`, asset upload/delete, and session launch server-side. **`Api::V1::Internal::*` (usage_statistics, ws_auth) are EXCLUDED** (service-to-service, non-user auth) via `skip_before_action :dynamic_authorize!` + `skip_after_action :verify_authorized`.
- **Client cannot own a project:** don't offer clients in owner-assignment UI; project creation sets owner to the (admin/employee) creator. **OPEN QUESTION 4:** add a model validation forbidding a `viewer` project owner, or rely on UI + creation flow?
- **`Project.for_user`** (`app/models/project.rb`): a client is not an admin, so they see only owned + collaborated; since clients shouldn't own, they see collaborated projects — correct.
- **`enforce_onboarding`** still applies to clients until `completed`; the relaxed guards + `can_complete_onboarding?` let them reach it without agents.
- **Privilege escalation:** `Projects::MembersPolicy#create?/destroy?` change `project_accessible?` → `project_writable?` so a client can't add/remove collaborators (overlaps #211).
- **OPEN QUESTION 1 (RESOLVED by product):** global client type vs per-project role — settled as **global**. (Research companion §6.1 leaned per-project on industry precedent; the product decision overrides for the external-observer use case.)
- **OPEN QUESTION 2 (UX):** client onboarding — collapse to Profile→Complete with hidden FE steps over the existing linear states (recommended), vs a dedicated transition. Also: should clients enter position/language at all, or onboard instantly?
- **OPEN QUESTION 3 (ENG — now IN scope for #213):** Full API Punditization is settled as part of #213 (see §4). What remains genuinely open/deferred: (a) OWNER/ADMIN gating on the API tree (beyond read-only) — the new `Api::` policies classify read vs write for the client tier; tightening specific writes to owner/admin only (e.g. board create is owner-only in the web `BoardsPolicy`) overlaps ticket #211 and can be layered into the same policies later; (b) service-layer defense-in-depth (`WorkflowService.start` / `TaskService.trigger_workflow` / `SessionService.create_and_start`). Decide whether to inherit the `Api::V1::Projects::*` policies from their `Web::Company::Projects::*` counterparts (single classification source) or copy.
- **OPEN QUESTION 4 (PRODUCT):** may a client ever be a project owner? Assumed no.

## 6. Acceptance Criteria Mapping

| Acceptance criterion | Satisfied by |
|---|---|
| A `viewer` (client) role exists and can be assigned | Enum value (`user.rb:20`); assignable via company Members invite (`ALLOWED_ROLES`, `InviteUserModal`), with the domain-matching exemption allowing external-domain emails; added to a project as a collaborator to grant read visibility. |
| A client can read workflows, boards, assets, analytics | Reads → `project_accessible?` in web `WorkflowsPolicy#index/show/builder`, `BoardsPolicy#show`, `AssetsPolicy`, `AnalyticsPolicy#index`, `SessionsPolicy`, AND the new `Api::V1::Projects::*` read actions (board tasks `index?/show?/workflow_runs?`, assets `download?`, etc. — §4 table); API GET reads also pass `deny_read_only_mutation!`. |
| A client cannot start a run or launch a session — hidden in UI and blocked server-side | Web: `WorkflowRunsPolicy` run actions + `AixleBuilderPolicy#start?/finish?` → `project_writable?`. API (the real path): `Api::V1::Projects::Board::TasksPolicy#trigger_workflow?` → `project_writable?` (403 via `dynamic_authorize!`), `Api::V1::TerminalSessionsPolicy#create?` → `!read_only?` plus the explicit `#create` guard; `deny_read_only_mutation!` backstops both. UI: `projectPermissions.canExecute` hides controls. |
| A client cannot create/edit/delete workflows/boards/assets — server-side | Per-action `Api::V1::Projects::*` policies (§4 table) deny every write for `read_only?` via `dynamic_authorize!` (board tasks/columns/bindings, assets, workflows/steps/triggers, workflow_run_assets export), fail-closed by `Pundit::NotDefinedError`→403 and the `deny_read_only_mutation!` backstop; web `WorkflowsPolicy` writes + `Projects::MembersPolicy#create?/destroy?` → `project_writable?`. |
| A client completes onboarding without configuring/running an agent | `can_advance_to_authenticated?` relaxes `step3→step4`; `can_complete_onboarding?` no longer requires agents for clients; `OnboardingPage.tsx` collapses agent steps. |
| A client is exempt from email/domain matching | `email_domain_matches_company` returns early for `read_only?` (`user.rb`), so an external-domain invite saves; clients bypass the domain-matched OAuth self-signup entirely. |
| Authorization enforced server-side, not only UI | Web mutations gated by `project_writable?` (Pundit); full api/v1 tree gated by per-action `Api::` policies via `dynamic_authorize!`, fail-closed via `Pundit::NotDefinedError`→403, backstopped by `deny_read_only_mutation!`, and regression-guarded by `after_action :verify_authorized` (test). All Pundit/server-side. UI hiding is additive UX only (research companion §6.3). |

## 7. Test Plan

> Backend = Minitest (`docker compose exec -T web bin/rails test PATH`). FE = Vitest. Introduce a `test/policies/` tree.

### Model tests — `test/models/user_test.rb`
- `viewer?`/`read_only?` true for viewer, false for employee/admin/super_admin.
- `can_complete_onboarding?` true for a client with position+language but NO agent credentials; false without position/language.
- `can_advance_to_authenticated?` true for client regardless of credentials; non-client still requires `has_configured_agents?`.
- **Constraint (b):** a `viewer` with an email domain NOT matching `company.email_domain` **saves** (validation exempted); a non-viewer with a mismatched domain still fails `email_domain_matches_company`.
- A client still requires `company_id` (validation `:42`).

### State machine — `test/state_machines/user_onboarding_state_machine_test.rb`
- Client: `go_next` advances `step3 → step4` with zero `agent_credentials`; non-client blocked without credentials, allowed with. `complete` succeeds for a client with position+language and no agents.

### Web policy tests — `test/policies/web/company/projects/*_policy_test.rb`
For `WorkflowRunsPolicy`, `WorkflowsPolicy`, `SessionsPolicy`, `AssetsPolicy`, `AnalyticsPolicy`, `AgentsPolicy`, `ToolsPolicy`, `AixleBuilderPolicy`, `Projects::MembersPolicy` (instantiated with a `ProjectContext`):
- Client (collaborator): reads (`index?`/`show?`/`builder?`/`download?`/analytics) → true; every write/execute action → false; `Projects::MembersPolicy#create?/destroy?` → false.
- Employee collaborator: writes → true (no regression). Admin (same company, non-member): reads/writes → true via `accessible_by?` admin branch.

### API policy tests — `test/policies/api/v1/**/*_policy_test.rb` (one per new policy in the §4 table)
For every `Api::V1::…Policy` (instantiated with the matching `ProjectContext`/`BaseContext`):
- Client: each **R** action → true; each **W** action → false.
- Employee (collaborator / company member): all actions → true.
- Non-member: reads/writes → false (via `project_accessible?`).
- Cover the classification edge cases explicitly: `WorkflowRunAssetsPolicy#export?/export_all?` → false for client (W); `#index?/download?` → true (R). `Api::V1::AssetsPolicy#presign?/upload?` → false for client. `Api::V1::TerminalSessionsPolicy#create?` → false for client.

### API per-controller authorization — request tests `test/controllers/api/v1/**`
Prove enforcement end-to-end (not just policy units) for the highest-value controllers, viewer vs employee:
- `board/tasks_controller_test.rb` (EXISTS — extend): client POST `#create`/PATCH `#update`/DELETE `#destroy`/PATCH `#move`/POST `#trigger_workflow` → all 403; GET `#index`/`#show`/`#workflow_runs` → 200; employee mutations → success.
- `projects/assets_controller_test.rb`, `company/assets_controller_test.rb`, `projects/workflows_controller_test.rb`, `projects/workflows/steps_controller_test.rb`, `projects/workflows/triggers_controller_test.rb`, `projects/board/columns_controller_test.rb`, `projects/board/columns/workflow_bindings_controller_test.rb`, `projects/board/view_presets_controller_test.rb`, `projects/board/task/{assets,comments,gates}_controller_test.rb`, `projects/workflow_run_assets_controller_test.rb` (create as needed): client writes → 403, client reads → 200; employee writes → success.
- `terminal_sessions_controller_test.rb` (EXISTS — extend): client POST `#create` runnable `session_type` → 403; `auth_setup` → allowed (or blocked, per OQ); employee → 201.
- Confirm `deny_read_only_mutation!` alone still 403s a client POST even if a policy were (hypothetically) mis-classified — e.g. a targeted test stubbing a policy to `true` and asserting the verb backstop still denies.

### `Pundit::NotDefinedError` fail-closed test
- Register a throwaway controller/action under the api/v1 tree in the test app **without** a policy (or stub `Pundit.policy!` to raise `NotDefinedError`) and assert the response is **403**, not 500 — proving the `rescue_from Pundit::NotDefinedError` fail-closed path.

### `verify_authorized` tripwire test
- Assert the tripwire is active in test env: a controller under `Api::V1::ApplicationController` that (in a fixture/dummy) skips `dynamic_authorize!` without `skip_after_action :verify_authorized` raises `Pundit::AuthorizationNotPerformedError`. Conversely, assert the excluded `Api::V1::Internal::{UsageStatistics,WsAuth}Controller` requests succeed (200/accepted) with authentication skipped and are NOT subject to the tripwire (they `skip_after_action :verify_authorized`).

### Internal-namespace regression tests
- `internal/usage_statistics_controller_test.rb`, `internal/ws_auth_controller_test.rb` (create if absent): confirm they still function with no `current_user` (service auth) after `dynamic_authorize!` is globally enabled — i.e. the exclusion works and they don't 403/500.

### Onboarding + web request tests
- `test/integration/web/company/members_controller_test.rb`: invite with `role: "viewer"` and a **mismatched email domain** succeeds; `update` to `viewer` succeeds.
- `test/integration/web/company/projects/workflow_runs_controller_test.rb`: client POST `create`/`cancel` → not-authorized redirect; employee → success.
- `test/integration/web/onboarding_controller_test.rb` (extend): assert by STATE (silent-no-op semantics, §2). A **client** PATCH `go_next` from `step3` (no credentials) moves `onboarding_state` to `step4`; a **non-client** stays at `step3`. `complete` reaches `completed` for the client.
- Read-path smoke: client collaborator GET workflows/analytics/assets/boards → 200.

### Frontend tests (Vitest)
- `OnboardingPage.test.tsx`: `role==='viewer'` → "Select Agents"/"Authenticate" not rendered, step-1 Continue advances toward Complete; non-client unchanged.
- `WorkflowsPage.test.tsx`: `projectPermissions.canExecute === false` → Run/New/edit/delete absent; `true` → present.
- `SessionNewForm.test.tsx`: "Start Session" hidden/disabled when not executable.
- `InviteUserModal.test.tsx`: role select offers "Viewer".
- `MembersContent.test.tsx`: a `viewer` member renders a non-empty badge (guards the `ROLE_COLORS`/`ROLE_LABELS` regression); filter exposes "Viewer".
- Spot pages: `WorkflowRuns/ShowPage`, Assets, Agents/Tools/Mcp/Skills/Integrations/Repositories — mutate controls hidden for non-executors.

## 8. Risks & Rollout

- **Risk — incomplete web-policy coverage.** A missed action silently keeps a client able to mutate. Mitigation: audit every file under `app/policies/web/company/projects/` (incl. `board/`, `board/task/`, `workflows/`, `sessions/`) + the §7 policy matrix.
- **Risk — significantly larger scope than a single-role change.** Full API authorization means authoring ~20 new `Api::`-namespace policy classes (§4 table), flipping `dynamic_authorize!` on at the API root, and adding request tests per controller. This is the bulk of #213's effort and touches every api/v1 endpoint. Mitigation: inherit `Api::V1::Projects::*` policies from their `Web::Company::Projects::*` counterparts to keep classification in one place; land it behind the `NotDefinedError` fail-closed rescue and the `verify_authorized` tripwire so partial coverage is safe (denies, doesn't leak) and regressions are caught by the suite.
- **Risk — flipping `dynamic_authorize!` on globally breaks/500s existing API traffic** if a controller lacks a policy or a route action doesn't map cleanly to a policy method. Mitigation: `rescue_from Pundit::NotDefinedError` → 403 makes a missing policy fail **closed** rather than 500; author all §4 policies before enabling; run the full API request suite. **Critical:** verify the `Api::V1::Internal::*` exclusion lands FIRST (else the two service endpoints — with no `current_user` — would hit `dynamic_authorize!` and break Traefik ForwardAuth / usage ingest). Also re-verify `Api::V1::AssetsController` and `TerminalSessionsController` resolve their `< ApplicationController` to `Api::V1::ApplicationController` (they do — nested in `module Api; module V1`) so they get policies as intended.
- **Risk — `verify_authorized` in the wrong env.** Enabling the tripwire in production could turn a coverage bug into a 500. Mitigation: enable in test (and optionally dev) only; rely on `NotDefinedError`→403 for prod fail-closed.
- **Risk — verb backstop over/under-blocks.** `deny_read_only_mutation!` assumes verb ≈ intent. Verified all api/v1 mutations are non-GET and all GETs are genuine reads (against `config/routes.rb`); re-verify on route changes. It is a backstop, not the primary boundary (the per-action policies are).
- **Risk — base-policy refactor** (moving `project`/`project_accessible?` into the base and deleting per-file duplicates touches ~25 files). Mitigation: mechanical change + full policy/request suite.
- **Risk — onboarding guard.** Relaxing `step3→step4` must not let non-clients skip agent setup — guard branches on `onboarding_requires_agent?`; covered by state-machine tests.
- **Risk — domain-matching exemption too broad.** Ensure `return if read_only?` only skips the *domain* check, not `company_id` presence (kept) — clients still belong to a company. Covered by model tests.
- **Type drift / compile break.** Adding `'viewer'` to `UserRole` breaks `Record<UserRole,…>` in `MembersContent.tsx` and `Profile/Show.tsx` until a `viewer` key is added (blank badge at runtime otherwise). Grep `Record<UserRole` before declaring done; run `yarn tsc` + `yarn test`.
- **Rollout:** the model change is low blast radius (additive enum, guard-clause exemptions, no migration); the API-authorization change is the higher-risk, larger piece and should land in a deliberate order: (1) model + state machine + domain exemption + web policies + tests; (2) **API authorization** — add the `Api::V1::Internal::*` exclusion base, author all `Api::` policies (§4 table), add `rescue_from Pundit::NotDefinedError` + `deny_read_only_mutation!` + the `verify_authorized` tripwire, THEN flip `before_action :dynamic_authorize!` on the API root, with the full API request suite green; (3) `inertia_share` `projectPermissions`; (4) FE control-hiding + onboarding branch; (5) members UI viewer option. Manual pass: invite a client with an external-domain email → saves; onboarding completes without an agent; add as collaborator → reads work and every run/mutate path (web AND direct API call) 403s and is hidden; confirm Traefik ForwardAuth (`/api/v1/internal/ws_auth`) and usage ingest still work.
