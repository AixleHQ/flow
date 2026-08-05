---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 1
research_type: 'technical'
research_topic: 'Multi-company user membership (invites, company switching, profile, per-user dashboards)'
research_goals: 'Design how one user can belong to multiple companies: invitation mechanism (email invites, confirmations), company switching UX/mechanics, user profile with multiple companies, impact on the merged user-analytics dashboards, and all other code-level implications (auth, sessions, authorization, data scoping)'
user_name: 'Artem_Petrov'
date: '2026-07-02'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-02
**Author:** Artem_Petrov
**Research Type:** technical

---

## Research Overview

This report investigates how to let one user belong to multiple companies in the Aixle platform — the driving use case being a client company onboarded to the SaaS whose external users must be **invited** rather than auto-authorized by email domain. The research is codebase-first: four parallel deep audits mapped the User/Company model and auth flows, the Pundit authorization and company-scoping layer, the newly merged user-analytics dashboards (#303), and peripheral subsystems (Temporal/outbox, integrations, ActionCable, tests). Industry patterns (membership join model, invitation token design, workspace switching) were verified against current public sources.

Headline findings: the system is single-company-per-user at every layer, but the two hard blockers (global email uniqueness, domain-match validation) dissolve under a `CompanyMembership` join model with per-membership roles — which also generalizes the #213 viewer role into its more correct per-company form. The #303 usage dashboards currently aggregate by `user_id` only and must gain company scoping (via `joins(:project)`, since project-less session starts are disabled). Full details in the Executive Summary and section-by-section analysis below; a 5-phase expand/contract implementation plan (~3-4 weeks, 5 independent PRs) closes the report.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Multi-company user membership (invites, company switching, profile, per-user dashboards)
**Research Goals:** Design how one user can belong to multiple companies: invitation mechanism (email invites, confirmations), company switching UX/mechanics, user profile with multiple companies, impact on the merged user-analytics dashboards, and all other code-level implications (auth, sessions, authorization, data scoping).

**Technical Research Scope:**

- Current architecture analysis (codebase-first) — User ↔ Company relationships, authentication (email-domain based?), sessions, roles (incl. viewer role), data scoping
- Invitation mechanism — email invites, tokens, confirmations, edge cases (existing vs new user, re-invites, revocation)
- Company switching — where "current company" lives (session/DB), impact on controllers and Inertia props
- User profile with multiple companies — global vs per-company attributes, per-company roles
- User-analytics dashboards (#303, merged to develop) — scoping by company under multi-membership
- Industry patterns — Slack/Notion/GitHub orgs, canonical Rails Membership join-model approaches (web-verified)
- Hidden implications — email unique indexes, invariants, authorization, analytics, Temporal/outbox

**Research Methodology:**

- Primary source: deep codebase analysis of this repository
- Web research to verify industry patterns and best practices
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information

**Scope Confirmed:** 2026-07-02

## Current Architecture Analysis (Codebase Stack Baseline)

### Technology Stack Snapshot

Rails (Postgres, AASM state machines, Enumerize roles, Pundit authorization, Alba resources + Typelizer type generation) with an Inertia.js + React (Mantine) frontend; Temporal for workflows, a transactional outbox (`TriggerEvent`), ActionCable channels, and Docker-only dev/test execution. No tenancy gem (`acts_as_tenant` not used) — company scoping is explicit in every query, which matches the recommended row-level pattern for shared-database SaaS ([acts_as_tenant docs](https://github.com/ErwinM/acts_as_tenant), [Rails multi-tenancy overview](https://oneuptime.com/blog/post/2025-07-02-rails-multi-tenancy/view)).

### User ↔ Company Model (Single-Company-Per-User)

- `User belongs_to :company, optional: true` (`app/models/user.rb:24`) — direct FK, no join/membership table. `company_id` required unless `super_admin` (`user.rb:42`).
- **Email is globally unique** (`db/schema.rb:840`, `users.email` unique index + case-insensitive uniqueness validation `user.rb:36-38`). A composite `(company_id, email)` unique partial index also exists (`schema.rb:837`).
- **Email-domain gate on create**: `email_domain_matches_company` (`user.rb:163-173`) requires the user's email domain to equal `company.email_domain` — **already bypassed for `read_only?` (viewer) users** ("external clients have their own email domain"). Precedent for cross-domain membership exists.
- `Company.email_domain` is globally unique (`company.rb:41-42`); `Company.find_by_email_domain(email)` (`company.rb:68-71`) drives OAuth company assignment.
- Roles: global enum on `users.role` — `employee | admin | super_admin | viewer` (Enumerize, `user.rb:18`). Role is **per-user, not per-company**.
- User states: `active | pending | suspended | archived` (AASM). Pending users cannot sign in (`UserSignInForm` uses `User.active`).

### Authentication & Sessions

- Custom auth (no Devise): email/password (`Web::SessionsController`, `UserSignInForm`) + Google OAuth (`GoogleOmniAuthService`, `app/services/google_omni_auth_service.rb:22-49`).
- OAuth auto-assigns company by email domain; `company.auto_accept_users` decides `active` vs `pending` state.
- Session stores only `user_id` (`AuthConcern#sign_in`); `current_company ||= current_user.company` (`web/company/application_controller.rb:36-38`). **No mechanism to select a company.**

### Existing "Invitation" Flow (No Tokens, No Emails)

- Admin "invite" = creating a pending user in the company: `current_company.users.new(...merge(inviter: current_user))`, `state: "pending"` (`web/company/members_controller.rb:16-26`). Tracks `invited_by_id` / `invited_at` (`user.rb:12, 25-26, 127-132`).
- **No invitation email is sent** — only `ApplicationMailer` exists (no subclasses); SMTP config and `letter_opener` are wired but unused business-wise.
- No invite tokens, no acceptance step, no expiry — activation is manual by admin.

### Authorization & Company Scoping

- Pundit with dynamic dispatch (`AuthorizationConcern#dynamic_authorize!`), `BaseContext`/`ProjectContext` as pundit_user.
- Write-gating from #213: `project_writable? = project_accessible? && !read_only?` (`api/v1/application_policy.rb`).
- Tenant checks are all singular-company: `ProjectsPolicy#current_project` → `current_user.company.projects.find_by(id:)` (`projects_policy.rb:29`); `MembersPolicy#same_company?` → `target_user.company_id == current_user.company_id` (`members_policy.rb:25-29`); `Project.for_user` → `where(company_id: user.company_id)` for admins (`project.rb:51-58`); `ProjectCollaborator` validates `user.company_id == project.company_id` (`project_collaborator.rb:15-19`); ActionCable `SessionListChannel` uses `current_user.company` (`session_list_channel.rb:8-13`).
- Resources (Agent/Tool/Skill/MCPServer/Asset/ConfigItem) use polymorphic `scope` (Company/Project/System) with explicit `for_company`/`visible_for_project` scopes; `SessionService#scoped_resources` resolves via `session.user.company` (`session_service.rb:140-147`).

### Frontend Contract

- Inertia shared props: `current_user` (via `CurrentUserResource` with `one :company`), `projects` (`Project.for_user`), `permissions` (`is_admin`, `can_manage_members`, `can_manage_projects`) — all single-company (`web/application_controller.rb:11-31`, `web/company/application_controller.rb:14-24`).
- Generated type `CurrentUser.company: Company | null` (`app/frontend/types/generated/CurrentUser.ts`).
- App shell: `AppSidebar.tsx` — `SidebarWorkspaceSwitcher` shows `currentUser.company.name` (no switcher), `SidebarUserFooter` menu has only Profile/Sign Out (`AppSidebar.tsx:405-435`). Natural insertion points for a company switcher.
- Profile page shows a single read-only company field: "Company assignment is managed by administrators" (`pages/Profile/Show.tsx:707-791`).

### User-Analytics Dashboards (#303, merged via PR #327)

Route `/profile/usage` → `Web::ProfileController#usage` (`profile_controller.rb:17-62`) + services `UserAnalyticsService`, `UserAgentActivityService`, `UserSessionCostTokenUsageService`, `ActivityHeatmapService`.

- Target-user guard is company-scoped: `resolve_target_user` → `current_user.company.users.find(params[:user_id])` (`profile_controller.rb:100-104`; 404 for foreign companies is test-covered).
- **All aggregation queries are scoped by `user_id` only** — `user.terminal_sessions` and `WorkflowRun.for_user_in_period(user, since)` have no company filter (`user_analytics_service.rb:49-53, 66-69, 74-95`; same pattern in the other two services and the sessions list, `profile_controller.rb:52-60`). `TerminalSession` has **no `company_id` column** — company is implicit via optional `project`.
- Under multi-company membership, every widget (summary, project breakdown, agent activity, cost/token time series, heatmap, sessions list) would aggregate data across ALL of the user's companies — a cross-company data leak. The vulnerability is latent today only because a user has exactly one company.

### Peripheral Single-Company Assumptions

- `TriggerEvent belongs_to :company` and `TriggerEngine.record_event/publish/dispatch` route by a single `company_id` (`trigger_engine.rb:40-71, 107-113`).
- `Integration belongs_to :company` (NOT NULL) — Slack/GitHub/etc. per company; tools gated by `requires_integration` resolve through company scope.
- Container strategy picks scope `["Company", user.company_id]` when no project (`container_strategies/agent_session_strategy.rb:231`).
- `cannot_demote_last_admin` counts admins per `company.users` (`user.rb:199-208`).
- `BoardActivity` has actor (user) but no company_id — company is implicit via actor.
- Factories/seeds generate emails from `company.email_domain`; `sign_in(user)` test helper sets only `session[:user_id]`.
- Agent credentials are per-user (not per-company) — probably fine to keep global under multi-company.

### Baseline Verdict

The system is consistently single-company-per-user at every layer (schema, validations, OAuth, policies, channels, outbox, frontend types). The two hard blockers are the **global email unique index** + **domain-match validation**, and the implicit **`current_company = current_user.company`** resolution. The canonical fix direction, confirmed by industry practice, is a **membership join model** (`CompanyMembership: user_id, company_id, role, state, invited_by, token…`) with account-level entities (User, Company, Membership) outside the tenant scope ([acts_as_tenant](https://github.com/ErwinM/acts_as_tenant), [GoRails discussion](https://gorails.com/forum/how-to-attach-users-to-a-tenant-tenants-with-rails-multi-tenancy-apartment), [WorkOS: model your B2B SaaS with organizations](https://workos.com/blog/model-your-b2b-saas-with-organizations)).

_Sources: codebase (file:line cited inline); [acts_as_tenant](https://github.com/ErwinM/acts_as_tenant); [Rails multi-tenancy guide](https://oneuptime.com/blog/post/2025-07-02-rails-multi-tenancy/view); [WorkOS organizations modeling](https://workos.com/blog/model-your-b2b-saas-with-organizations); [Clerk multi-tenant SaaS architecture](https://clerk.com/blog/how-to-design-multitenant-saas-architecture)_

## Integration Patterns Analysis (Invitation Protocol & Company Switching)

### Invitation Data Flow: Extend the Pending-User Pattern to Memberships

Today an "invite" is `current_company.users.new(state: "pending", inviter: current_user)` (`members_controller.rb:16-26`). Under a membership model this becomes: **invite = create a `CompanyMembership` in state `invited`**, creating the `User` row lazily only if the email is unknown.

Recommended protocol (verified against [Rails 8 invitation flow write-ups](https://medium.com/deemaze-software/user-invitations-with-rails-8-authentication-ba229fab466e) and [SaaS invite-flow guides](https://supersaas.dev/docs/teams/invite-flow)):

1. Admin submits email (+ role) → find-or-initialize `User` by email (email stays **globally unique** — one identity, many memberships; this removes the need to drop the global unique index).
2. Create `CompanyMembership(user, company, role, state: :invited, invited_by, invited_at)`.
3. Generate a **purpose-scoped, expiring token** — Rails 8.1 has `generates_token_for :invitation, expires_in: 7.days` built in ([Rails 7.1+ generates_token_for](https://blog.saeloun.com/2023/11/14/rails-7-1-introduces-active-record-generate-token-for/)): stateless, tamper-proof (signed with `secret_key_base`), auto-invalidated when the embedded value changes (e.g. membership state) — no token column, no hashing bookkeeping. Industry guidance: ≥32 bytes entropy, single-use, ~7-day expiry, resendable ([token best practices](https://www.sequenzy.com/blog/how-to-create-team-invitation-emails-saas)).
4. Send `MembershipMailer.invitation(membership)` via `deliver_later` — first real mailer in the app; SMTP config + `letter_opener` are already wired (`config/settings.yml:35-41`, `routes.rb:174`).
5. Invitee opens `/invitations/:token` → `InvitationsController#show` resolves membership via `CompanyMembership.find_by_token_for(:invitation, token)`, branches on user/session state (matrix below).
6. Acceptance transitions membership `invited → active`; decline/revoke transitions to `declined`/`revoked`. Resend regenerates the (stateless) token.

### Acceptance Matrix: Existing vs New User × Session State

| Invitee state | Session state | Flow |
|---|---|---|
| No account | — | Pre-filled signup (set name/password **or** "Continue with Google"), then membership activates; onboarding runs once per user, not per company |
| Has account | Logged out | Redirect to login (email pre-filled, Google or password), then auto-accept on return — store pending token in session across the auth round-trip |
| Has account | Logged in, same email | One-click accept screen: "«Acme» invites you — Accept / Decline" |
| Has account | Logged in as a *different* user | Show "invitation is for X@…, you are Y@…" → offer logout-and-continue; never silently attach to the wrong identity |

Key security rule (multi-source, [Auth0 B2B onboarding](https://auth0.com/blog/user-onboarding-strategies-b2b-saas/), [supersaas invite flow](https://supersaas.dev/docs/teams/invite-flow)): the invite email address is the identity anchor — accept only into the `User` whose email matches the invitation, and treat the emailed link itself as email-ownership proof (it substitutes for the confirmation step; no separate email confirmation needed).

### OAuth Interplay

`GoogleOmniAuthService` (`google_omni_auth_service.rb:22-49`) stays almost intact under memberships:

- `User.find_or_initialize_by(email:)` remains a **global** identity lookup — correct.
- Domain auto-assignment (`Company.find_by_email_domain`) becomes "create a *membership* in the domain company if none exists", instead of setting `user.company`. It must **not** run when the user already has memberships (an invited external user logging in via Google must not get attached to their own-domain company unless that company exists and policy says so).
- The invited-external-user case is the whole point: their domain matches no company (or a different company) — membership comes from the invitation, so the domain-match validation moves from `User` to "auto-join" logic only. The `read_only?` bypass (`user.rb:167`) generalizes into: **domain-match is a rule for auto-join, not for membership**.
- Existing PKCE/streamlined-linking guidance applies unchanged ([Google account linking](https://developers.google.com/identity/account-linking/oauth-linking)).

### Company Switching Mechanics

Session-based switcher (industry default for users in multiple tenants, [WorkOS](https://workos.com/blog/model-your-b2b-saas-with-organizations), [Clerk](https://clerk.com/blog/how-to-design-multitenant-saas-architecture)):

- Store `session[:current_company_id]`; `current_company` resolves it **validated against active memberships**, falling back to the user's default/first membership: `current_user.memberships.active.find_by(company_id: session[:current_company_id]) || current_user.memberships.active.first`.
- `POST /company/switch` (params: `company_id`) → validate membership → write session → `redirect_to company_projects_path`. With Inertia this is a plain visit; all `InertiaRails.always` shared props re-evaluate automatically on the next request — no client cache to invalidate beyond the full-page visit.
- URL-slug tenancy (`/:company_slug/...`) was considered and rejected for now: it gives shareable URLs but forces rewriting the entire `routes.rb`/`routes.ts` surface and all `*_path` helpers; session-based switching is a strictly smaller diff and matches the existing `company_*` route namespace. Revisit only if cross-company deep-linking becomes a product need ([tenant routing tradeoffs](https://aws.amazon.com/blogs/networking-and-content-delivery/tenant-routing-strategies-for-saas-applications-on-aws/)).
- **ActionCable**: `SessionListChannel` resolves `current_user.company` at subscription time (`session_list_channel.rb:8-13`) → must read the same session-validated company (connection has access to cookies/session), and the frontend must re-subscribe after a switch (full Inertia visit already remounts providers).
- **API v1 / terminal sessions**: agent-launched sessions resolve context via `current_user.company` (`api/v1/terminal_sessions_controller.rb:18,73`) — must switch to the session's project company or an explicit `company_id` param, since API calls don't share the web session's switcher state. Container strategy scope `["Company", user.company_id]` (`agent_session_strategy.rb:231`) must derive company from the project/session, not the user.

### Frontend Contract Changes

- `CurrentUserResource`: `one :company` → `many :memberships` (company + per-company role + state) **plus** `current_company` (the resolved one), so `CurrentUser.company` consumers can migrate incrementally; regenerate Typelizer types.
- Shared `permissions` props (`is_admin`, `can_manage_members`…) become **per-current-company** — computed from the active membership's role, not `user.role`.
- Switcher UI: `SidebarWorkspaceSwitcher` (company name is already rendered there) becomes a dropdown when `memberships.length > 1`; pattern: always-visible switcher showing the user's role per company, Slack-style ([Slack workspace switching](https://slack.com/help/articles/1500002200741-Switch-between-workspaces)).
- Invitation pages are unauthenticated Inertia pages (like `Auth/LoginPage`): `Invitations/Show` (accept/decline/signup variants).

_Sources: [Rails generates_token_for](https://blog.saeloun.com/2023/11/14/rails-7-1-introduces-active-record-generate-token-for/); [Rails 8 user invitations](https://medium.com/deemaze-software/user-invitations-with-rails-8-authentication-ba229fab466e); [devise_invitable (reference design)](https://github.com/scambra/devise_invitable); [SaaS invitation token practices](https://www.sequenzy.com/blog/how-to-create-team-invitation-emails-saas); [Supersaas invite flow](https://supersaas.dev/docs/teams/invite-flow); [Auth0 B2B onboarding](https://auth0.com/blog/user-onboarding-strategies-b2b-saas/); [Google account linking](https://developers.google.com/identity/account-linking/oauth-linking); [WorkOS organizations](https://workos.com/blog/model-your-b2b-saas-with-organizations); [Clerk multi-tenant architecture](https://clerk.com/blog/how-to-design-multitenant-saas-architecture); [AWS tenant routing](https://aws.amazon.com/blogs/networking-and-content-delivery/tenant-routing-strategies-for-saas-applications-on-aws/); [Slack workspace switching](https://slack.com/help/articles/1500002200741-Switch-between-workspaces)_

## Architectural Patterns and Design

### Data Architecture: `CompanyMembership` Join Model

Canonical B2B pattern — globally-unique User + org-scoped role on the membership row, unique on `(user_id, company_id)` ([WorkOS user management](https://workos.com/blog/user-management-for-b2b-saas), [Logto org RBAC](https://blog.logto.io/organization-and-role-based-access-control), [Flightcontrol multi-tenant data modeling](https://www.flightcontrol.dev/blog/ultimate-guide-to-multi-tenant-saas-data-modeling)):

```ruby
create_table :company_memberships do |t|
  t.references :user,    null: false, foreign_key: true
  t.references :company, null: false, foreign_key: true
  t.string  :role,  null: false, default: "employee"  # employee | admin | viewer
  t.string  :state, null: false, default: "invited"   # invited | active | suspended | revoked
  t.bigint  :invited_by_id
  t.datetime :invited_at, :accepted_at
  t.timestamps
  t.index [:user_id, :company_id], unique: true
end
```

Design decisions and their rationale:

- **Role moves to the membership** (`employee | admin | viewer`). This *supersedes the #213 global-viewer semantics* and is strictly more correct for the target use case: the same person is `employee`/`admin` in their own company and `viewer` (or `employee`) in the client company. `super_admin` stays on `users.role` — it's a platform-level attribute with `company_id: nil`, orthogonal to memberships.
- **User keeps global identity fields**: email (still globally unique), password/OAuth credentials, name/avatar, `preferred_agent_language`, `selected_agents`, onboarding state, agent credentials — onboarding and credentials run once per human, not per company (`user.rb`, onboarding guards `user.rb:100-124`).
- **Two-level lifecycle**: `users.state` keeps global meaning (`pending` = awaiting domain auto-join approval, `suspended`/`archived` = platform-wide); `membership.state` handles the per-company lifecycle (`invited → active`, per-company suspend/revoke). AASM on the membership mirrors the existing `UserStateMachine` idiom.
- **`users.company_id` is retired in phases**: backfill `CompanyMembership(role: user.role, state: user.state == "pending" ? "invited" : "active")` from it, dual-write during transition, drop last. The `email_domain_matches_company` validation (`user.rb:163-173`) is deleted from User and re-expressed as auto-join policy in `GoogleOmniAuthService`.
- **Last-admin guard** (`cannot_demote_last_admin`, `user.rb:199-208`) moves to `CompanyMembership` (count active admin memberships per company).

### Authorization Refactor (Pundit Layer)

The existing dynamic-dispatch Pundit setup absorbs this cleanly because company context is already centralized in `policy_context`:

- `BaseContext.new(current_user, params)` → `BaseContext.new(current_user, params, company: current_company)`, exposing `context.membership` (`current_user.memberships.active.find_by(company: company)`). `ProjectContext` derives company from `project.company` — which makes API-side authorization (where there is no web session) company-correct for free.
- Policy predicates change mechanically: `current_user.admin?` → `membership.admin?`; `read_only?` → `membership.viewer?`; `same_company?` → target has an active membership in `context.company` (`members_policy.rb:25-29`); `ProjectsPolicy#current_project` → `context.company.projects.find_by(id:)` (`projects_policy.rb:29`).
- Model-level checks: `Project.for_user` admin branch → parameterize by company (`project.rb:51-58`); `ProjectCollaborator#user_belongs_to_same_company` → "user has an active membership in project's company" (`project_collaborator.rb:15-19`).
- The #213 write-gate generalizes: `project_writable? = project_accessible? && !membership_for(project.company).viewer?`.

Confidence: HIGH — this is a mechanical rewrite of ~15 identified call sites, all catalogued in the baseline section.

### Data Isolation for Dashboards & Sessions (the #303 fix)

Root cause: `TerminalSession` has no `company_id`; company is implicit via `user.company` or optional `project`. Two options:

1. Denormalize `company_id` onto `terminal_sessions` (set at creation; backfill from `project.company_id`). Makes the tenant boundary explicit on the highest-volume table and follows the row-level tenancy rule "every tenant-owned table carries the tenant id" ([Clerk](https://clerk.com/blog/how-to-design-multitenant-saas-architecture), [acts_as_tenant](https://github.com/ErwinM/acts_as_tenant)).
2. **Join through `projects.company_id`.** ✅ Recommended given a product constraint confirmed during research: starting project-less sessions is now disabled, and all usage analytics filter on `USAGE_SESSION_TYPES = %w[agent_session workflow_step]` (`user_agent_activity_service.rb:7`) — both project-bound. So `joins(:project).where(projects: { company_id: })` fully covers the #303 services with no migration. The only project-less rows are `auth_setup` sessions (credential setup, excluded from usage analytics) and possibly historical data — verify with a one-off count before relying on the join; if legacy usage rows with `project_id IS NULL` exist, backfill or accept their exclusion. Option 1 remains an optional hardening step later (DB-level guarantee, cheaper aggregates), not a prerequisite.

> **Update (2026-07-28): Option 1 shipped after all.** The join covers the #303
> dashboards as described, but per-company agent credentials made the column
> mandatory for a different reason: `auth_setup` sessions are project-less and
> they are the sessions that CREATE a credential, which is billed to one
> company. With no `terminal_sessions.company_id`, that tenant had to be guessed
> from "the user's first membership" — a coin flip for a multi-company user, and
> the thing being guessed is who pays. `SessionCompany` now resolves it from the
> column, falling back to the project, and never from a membership.

`WorkflowRun` already reaches company via `project` — scoping `for_user_in_period` by company is a join filter. `TriggerEvent`/`BoardActivity` already carry or imply company and stay as-is; container strategy scope `["Company", user.company_id]` (`agent_session_strategy.rb:231`) switches to session/project-derived company.

Product rule for `/profile/usage`: the dashboard always renders **current-company data only** (both self-view and colleague-view); switching company re-renders with that company's slice. Cross-company "all my activity" view is deliberately out of scope — it would surface company A's cost data while in company B's context.

### Security Architecture

- **Tenant-leak invariant**: every tenant-scoped read goes through `current_company` (membership-validated) or a project whose company was membership-checked. Session value `session[:current_company_id]` is never trusted directly — always re-validated against active memberships on each request (cheap indexed lookup, cacheable per-request).
- Invitation tokens: purpose-scoped, expiring, invalidated by membership state transition (`generates_token_for` embeds state) — a revoked invite dies instantly without token bookkeeping.
- Membership revocation must also invalidate the *switcher*: if the revoked company is in the user's session, next request falls back to another active membership or logout — this comes free from the "validate on every request" rule.
- ActionCable: `SessionListChannel` re-validates membership at subscription; existing subscriptions die on page visit after switch.

### Deployment & Migration Sequencing

> **Superseded by what shipped (2026-07-28).** The five phases below were never
> executed as separate deploys. The work landed as a **single cutover** — no
> dual-write phase — in four commits on `feat/multi-company-membership`, each
> `check_all`-green: the membership model + invitations + switcher together, then
> the gaps the rebase onto develop exposed, then per-company re-onboarding, then
> per-company agent credentials. Two decisions also diverge from the plan below:
> `terminal_sessions.company_id` WAS added after all (phase 2 called it
> optional) because project-less `auth_setup` sessions create a per-company
> billed credential and their tenant cannot be inferred; and onboarding moved
> wholesale onto `company_memberships` (the plan assumed it stayed per-user).
> Kept for the reasoning, not as a runbook.

Phased, each phase shippable and `check_all`-green (per project convention; data migrations idempotent):

1. **Schema + backfill**: create `company_memberships`, idempotent data migration from `users.company_id`/`role`/`state`, dual-write on user create/invite. No behavior change.
2. **Read-path switch**: `current_company` resolves via session+membership (falls back to sole membership — zero visible change for single-company users); policies/contexts move to membership predicates; `terminal_sessions.company_id` added + backfilled; #303 services take `company:`.
3. **Invitations**: `MembershipMailer`, `InvitationsController`, members-page "Invite" now sends real email; acceptance matrix flows.
4. **Switcher UI**: `CurrentUserResource.memberships`, `SidebarWorkspaceSwitcher` dropdown, `POST /company/switch`.
5. **Cleanup**: drop `users.company_id` and non-super-admin roles from users; remove domain-match validation remnants.

_Sources: [WorkOS: user management for B2B SaaS](https://workos.com/blog/user-management-for-b2b-saas); [Logto: organization RBAC](https://blog.logto.io/organization-and-role-based-access-control); [Flightcontrol: multi-tenant SaaS data modeling](https://www.flightcontrol.dev/blog/ultimate-guide-to-multi-tenant-saas-data-modeling); [Clerk: multi-tenant architecture](https://clerk.com/blog/how-to-design-multitenant-saas-architecture); [Frontegg: SaaS roles & permissions](https://frontegg.com/guides/roles-and-permissions-handling-in-saas-applications)_

## Implementation Approaches and Technology Adoption

### Adoption Strategy: Expand → Backfill → Contract

The five-phase plan follows the expand/contract (parallel change) pattern — each phase backward-compatible, old and new paths coexisting until cutover ([expand-contract in practice](https://dev.to/jp_fontenele4321/the-expand-and-contract-pattern-for-zero-downtime-migrations-445m), [zero-downtime migration guide](https://www.deployhq.com/blog/database-migration-strategies-for-zero-downtime-deployments-a-step-by-step-guide)). Single-company users must see zero behavior change until Phase 4 ships the switcher.

### Phase-by-Phase Work Breakdown (file-level)

**Phase 1 — Schema + backfill (expand).** New model `app/models/company_membership.rb` (AASM state machine mirroring `UserStateMachine` idiom, Enumerize role, `generates_token_for :invitation, expires_in: 7.days`, last-admin validation). Migration pair: create table + idempotent data migration backfilling from `users.company_id`/`role`/`state` (project convention: seed + idempotent data migration). Dual-write: `after_save` sync or explicit writes in the two user-creation sites (`members_controller.rb:16`, `google_omni_auth_service.rb:22-49`, admin company creation `admin/companies_controller.rb`). Factories: `company_membership` factory; extend `users.rb` factory traits.

**Phase 2 — Read-path switch.** `AuthConcern`: add `current_membership`/`current_company` resolution from `session[:current_company_id]` validated against `memberships.active`, fallback to first active membership. Rewrite the ~15 catalogued call sites (policies `projects_policy.rb:29`, `members_policy.rb:25-29`, controllers `profile_controller.rb:100-104`, `api/v1/terminal_sessions_controller.rb:18,73`, channel `session_list_channel.rb:8-13`, models `project.rb:51-58`, `project_collaborator.rb:15-19`, container strategy `agent_session_strategy.rb:231`). #303 services gain a `company:` kwarg with `joins(:project).where(projects: { company_id: })` (project-less usage sessions no longer exist; verify legacy rows with a one-off count first). `BaseContext`/`ProjectContext` gain `membership`.

**Phase 3 — Invitations.** `MembershipMailer#invitation` (+ `app/views/membership_mailer/`), `Web::InvitationsController` (`show` — token resolution + branching, `accept`, `decline`), routes `get/post /invitations/:token`, unauthenticated Inertia pages `Invitations/Show.tsx` (accept / signup / wrong-account variants). Members page: replace "create pending user" with "create membership + send email"; add Resend/Revoke actions and `invited` badge to `MembersContent.tsx`. OAuth: `GoogleOmniAuthService` reworked — global identity find-or-create; domain auto-join only when the user has no memberships; pending-invite token carried through the OAuth round-trip via session.

**Phase 4 — Switcher + profile.** `CurrentUserResource`: add `many :memberships` (company, role, state) + `current_company`; regenerate Typelizer types (memory: nested keys stay snake_case; regen command). `POST /company/switch` endpoint; `SidebarWorkspaceSwitcher` becomes a Mantine Menu when `memberships.length > 1` (show role per company); `Profile/Show.tsx` company card → companies list with per-company role badges and "Leave company" (self-removal, guarded by last-admin rule). Shared `permissions` props computed from `current_membership.role`. `/profile/usage` keeps current-company scoping from Phase 2 — switching companies naturally re-renders that company's slice.

**Phase 5 — Contract.** Drop dual-write, drop `users.company_id` + non-super-admin `users.role` usage, delete `email_domain_matches_company` from User, remove `read_only?`-global predicates in favor of membership predicates (grep-driven cleanup). Keep `users.role = super_admin` only.

### Testing and Quality Assurance

- **Backend (minitest, Docker-only per project convention):** model tests for membership state machine + last-admin + token expiry/invalidation; integration tests per acceptance-matrix row (new user, existing logged-out, logged-in same, logged-in different); switcher tests (switch → scoped props; revoked membership → fallback); **cross-company isolation tests are the highest-value additions** — extend the existing pattern in `profile_usage_controller_test.rb:107-113` to: usage dashboards show only current-company sessions for a dual-membership user; members page never lists the other company; projects list scoped per current company.
- **Frontend (Vitest + jsdom, backendless, mock `@inertiajs/react` per established FE testing system):** switcher rendering/branching, invitation page variants, members-page invite/resend/revoke states. Forms use `zod4Resolver` (project constraint).
- **Full gate:** `docker compose exec -T web make check_all` green before every phase's PR.

### Risk Assessment and Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Cross-company data leak via missed `user.company` call site | Critical | Grep-audit `\.company\b` / `company_id` at Phase 2 end; isolation test suite; category-killer framing ([Clerk](https://clerk.com/blog/how-to-design-multitenant-saas-architecture)) |
| Backfill drift under dual-write | Medium | Idempotent migration re-runnable; reconciliation check comparing `users.company_id` vs membership rows before Phase 5 contract |
| OAuth auto-join attaching invited externals to wrong company | High | Auto-join only when user has zero memberships; explicit test for "invited user with foreign domain logs in via Google" |
| Session fixation on `current_company_id` | Medium | Never trust session value — membership-validated every request; reset on membership revoke |
| `viewer` semantics change (#213 global → per-membership) | Medium | Product decision to record explicitly; migrate existing viewers to viewer-role memberships (behavior identical for single-membership users) |
| Email deliverability (first real mailer) | Low | `letter_opener` in dev; SMTP env vars already provisioned; invites resendable |

### Effort Estimate (confidence: MEDIUM)

Phase 1: ~2-3 days. Phase 2: ~3-5 days (the grep-driven rewrite + tests dominate). Phase 3: ~4-6 days (mailer, controller, 3 FE pages, OAuth rework). Phase 4: ~3-4 days (resource/types/switcher/profile). Phase 5: ~1-2 days. Total ≈ 3-4 weeks of focused work, shippable in 5 independent PRs.

### Success Metrics

- Zero cross-company rows in any dashboard/list for a dual-membership test user (automated isolation suite).
- Invitation funnel instrumented: sent → opened → accepted (states already on membership; `TriggerEvent` outbox can carry `membership.invited/accepted` events for future automation).
- No regression for single-company users (entire existing test suite passes unchanged through Phase 4).

_Sources: [Expand-contract pattern](https://dev.to/jp_fontenele4321/the-expand-and-contract-pattern-for-zero-downtime-migrations-445m); [Zero-downtime migration strategies](https://www.deployhq.com/blog/database-migration-strategies-for-zero-downtime-deployments-a-step-by-step-guide); [strong_migrations-style batched backfills](https://medium.com/@sohail_saifii/database-migrations-at-scale-zero-downtime-strategies-b72be4833519); prior sections' codebase citations_

## Research Synthesis

### Executive Summary

Aixle today binds every user to exactly one company through a direct `belongs_to :company`, a globally unique email, and a create-time domain-match validation; "invitations" are admin-created pending users with no tokens and no emails. Supporting the client-company use case requires a **`CompanyMembership` join model** — the canonical B2B SaaS pattern — carrying the per-company role (`employee | admin | viewer`) and lifecycle (`invited → active | suspended | revoked`), while User keeps global identity (email, credentials, onboarding, agent credentials) and the platform-level `super_admin` flag. Crucially, **email stays globally unique** (one identity, many memberships), so the scariest-looking schema blocker never needs to be broken, and the #213 viewer domain-bypass reveals the codebase was already drifting toward this design.

The invitation mechanism builds on Rails 8.1's `generates_token_for` (stateless, expiring, state-invalidated tokens), the app's first real mailer (SMTP + letter_opener already wired), and a four-branch acceptance matrix keyed on the invitee's account/session state. Company switching is session-based (`session[:current_company_id]`, validated against active memberships on every request) with a `SidebarWorkspaceSwitcher` dropdown; URL-slug tenancy was evaluated and rejected as a disproportionate routing rewrite. The #303 usage dashboards are the sharpest latent leak — all aggregations are `user_id`-only — and are fixed by passing `company:` into the four services with a `joins(:project)` scope, since usage session types are always project-bound.

**Key Technical Findings:**

- Single-company assumptions are pervasive but *catalogued*: ~15 authorization/scoping call sites, 4 dashboard services, ActionCable channels, container strategy, OAuth auto-assignment, last-admin guard.
- The membership model converts the domain-match validation from a User invariant into an **auto-join policy** (OAuth users with a matching domain and no memberships), which is exactly the semantics the client-company use case needs.
- Per-membership roles supersede #213's global viewer — one person can be admin at home and viewer at the client — with identical behavior for existing single-membership users.
- API/agent-side authorization must derive company from the **project**, not the user or web session; this falls out naturally from `ProjectContext`.

**Technical Recommendations:**

1. Adopt `CompanyMembership` with role+state on the membership; keep email globally unique; retire `users.company_id`/`role` via expand→backfill→contract.
2. Invitations: membership-in-`invited`-state + `generates_token_for` + `MembershipMailer`; emailed link doubles as email-ownership proof.
3. Switching: session-based, membership-validated per request; full Inertia visit re-evaluates all shared props.
4. Scope #303 services by current company via project join; product rule — `/profile/usage` shows only the current company's slice.
5. Ship in 5 independent, `check_all`-green PRs (~3-4 weeks); cross-company isolation tests for a dual-membership user are the highest-value QA investment.

### Open Product Decisions — RESOLVED 2026-07-27

All five were decided while rebasing `feat/multi-company-membership` onto
develop. Recorded here because the implementation now depends on them.

1. **Viewer semantics** — CONFIRMED: global viewer migrates to per-membership
   viewer. A viewer is read-only and nothing further is hidden: they may see
   cost/usage, members and settings of a company they are a guest in. The
   `canExecute` write-gate is the whole of the restriction.
2. **Who can invite** — company admins only, from the company members page, and
   an external may be invited at **any** role (not viewer-only). Email invite
   plus Google domain auto-join are the ONLY ways into a company: there is no
   self-serve company creation and no public signup.
3. **Default landing company** — last used, persisted in `users.last_company_id`.
   Session-only storage snapped back to the oldest membership on every new
   session. Re-validated against active memberships on each request, so a
   revoked company can never resolve.
4. **Cross-company self view** — CONFIRMED out of scope. `/profile/usage` is
   always a current-company slice, and now states which company it is showing.
5. **Auto-join vs invitations** — CONFIRMED: invitation always wins.
   `GoogleOmniAuthService#ensure_domain_membership` skips any user who already
   has a membership in **any** state, so an invited external is never
   domain-auto-joined into their own-domain company.

Decisions taken during implementation that this report did not anticipate:

6. **Personal MCP tokens** are session-less, so there is no "current company" to
   lean on: company is derived from the target **project**, and the few tools
   with no project take an explicit `company_id`, erroring when the user belongs
   to more than one company. Ambiguity is never resolved by picking one.
7. **Removing a member** revokes the membership and never touches the `User`
   row. Since `Project#owner_belongs_to_company` requires an active membership,
   a revoked owner would leave their projects failing validation on any later
   save — so revocation transfers owned projects to the company's oldest active
   admin, and is refused outright when no other admin exists.
8. **Soft-deleted users** keep their membership rows, so `restore!` is lossless;
   they are filtered at every read instead — authentication (both password and
   OAuth), `Company#users`, `User.for_company`, and the members list.
9. **Agent credentials after a role change**: onboarding skips the agent step for
   a viewer-everywhere user and never re-runs, so gaining a non-viewer role
   leaves them with empty agent pickers. `User#needs_agent_setup?` drives a
   sidebar nudge rather than dragging them back through onboarding.

### Table of Contents

1. Technical Research Scope Confirmation
2. Current Architecture Analysis (Codebase Stack Baseline) — models, auth, invitations-as-is, authorization, frontend contract, #303 dashboards, peripheral assumptions
3. Integration Patterns Analysis — invitation protocol, acceptance matrix, OAuth interplay, company switching, frontend contract changes
4. Architectural Patterns and Design — `CompanyMembership` schema, authorization refactor, dashboard isolation, security architecture, migration sequencing
5. Implementation Approaches and Technology Adoption — phase-by-phase work breakdown, testing, risks, effort estimate
6. Research Synthesis (this section)

### Methodology & Source Verification

Primary source: the repository itself — four parallel read-only audit agents covering auth/models, authorization/scoping, the #303 feature (via its merge commit), and peripheral subsystems; all claims carry `file:line` citations. Secondary: current web sources (WorkOS, Clerk, Logto, Frontegg, Rails core documentation and community write-ups, AWS/Google docs) cited inline per section; multi-source validation applied to the membership pattern, token design, and switching approach. Confidence: HIGH on codebase facts and the membership pattern; MEDIUM on effort estimates and on legacy project-less usage rows (verify with a one-off count). One user-supplied constraint incorporated mid-research: project-less session starts are disabled, which changed the dashboard-scoping recommendation from column denormalization to a project join.

### Conclusion & Next Steps

The migration is substantial but mechanical: every single-company assumption is now enumerated with a file:line reference, and the five-phase plan keeps each step shippable with zero visible change for single-company users until the switcher lands. Recommended next steps: (1) resolve the five open product decisions above; (2) run `/bmad-create-prd` or epics/stories breakdown from this report; (3) start Phase 1 (schema + backfill) as a standalone PR.

**Technical Research Completion Date:** 2026-07-02
