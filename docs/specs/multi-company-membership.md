---
title: 'Multi-company user membership: invites, switcher, scoped dashboards'
type: 'feature'
created: '2026-07-02'
baseline_commit: 'b0c38091'
status: 'done'
context:
  - 'docs/research/technical-multi-company-user-membership-research-2026-07-02.md'
  - 'CLAUDE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Users are hard-bound to one company (`users.company_id`, global role enum, email-domain validation), so client-company users cannot be invited; "invitations" send no email and have no tokens; usage dashboards (#303) aggregate by `user_id` only and would leak cross-company data.

**Approach:** Full cutover (no dual-write) to a `CompanyMembership` join model with per-company role+state, token-based email invitations, a session-based company switcher, and company-scoped analytics — per the research report in `context`.

## Boundaries & Constraints

**Always:**
- Email stays globally unique; User keeps global identity (password/OAuth, name, onboarding, agent credentials).
- `session[:current_company_id]` is validated against **active** memberships on every request; fallback = last used, then first active membership.
- Roles `employee | admin | viewer` live ONLY on membership; `users.role` is replaced by boolean `users.super_admin` (keep `super_admin?` predicate API).
- Any role may be granted on invite, regardless of email domain; domain-match becomes OAuth auto-join policy only (auto-join runs only when user has zero memberships; an invitation always wins).
- `/profile/usage` and members/projects lists render current-company data only; #303 services take `company:` and scope via `joins(:project).where(projects: { company_id: })`.
- Invitation tokens via `generates_token_for :invitation, expires_in: 7.days`; emailed link = email-ownership proof; accept only into the User whose email matches the invitation.
- Work happens in git worktree `.worktrees/multi-company` branched from `origin/develop`; all Rails/test commands run inside the `web` container with `cd /app/.worktrees/multi-company`.
- Existing single-company behavior unchanged for single-membership users (whole existing suite must pass, adapted only where role/company storage moved).

**Ask First:**
- Renaming/dropping any table or column beyond: drop `users.company_id`, `users.role`, `users.invited_by_id`, `users.invited_at`.
- Changes to Temporal workflows or `TriggerEngine` routing.
- Any new gem.

**Never:**
- URL-slug tenancy (`/:company_slug/...`); cross-company aggregate dashboards; dual-write/transition period; `devise_invitable`/`acts_as_tenant` gems; per-company onboarding or per-company agent credentials.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Invite new email | Admin invites unknown email + role | User row (no password) + membership `invited`; email sent with token link | Duplicate active membership → validation error shown on members page |
| Invite existing user | Email belongs to existing user (any company) | New membership `invited` for that user; email sent | Already invited → resend (new token), not duplicate |
| Accept, no session | Valid token, logged out, user has password | Login (email pre-filled) → auto-accept → membership `active`, redirected into inviting company | Expired/invalid token → error page with "ask for a new invite" |
| Accept, new user | Valid token, user has no password/OAuth | Pre-filled signup (password or Google) → accept → onboarding | Token email ≠ chosen identity → reject |
| Accept, wrong account | Logged in as different user | "Invitation is for X, you are Y" page; offer logout-and-continue | Never attach to logged-in mismatched user |
| Switch company | `POST /company/switch` with member company_id | Session updated; redirect to company projects; all props/permissions re-scoped | Non-member company_id → 404/403, session unchanged |
| Revoked mid-session | Current company membership revoked | Next request falls back to another active membership (or logout if none) | No stale access |
| OAuth, invited external | Google login, email domain matches no/other company, has membership | Sign in; NO auto-join to domain company | — |
| OAuth, fresh domain user | No memberships, domain matches company | Auto-join membership created (state per `auto_accept_users`) | No company match → user with zero memberships → pending screen |
| Usage dashboard | Dual-membership user opens `/profile/usage` | Only current company's sessions/workflows/costs in every widget | Colleague param from other company → 404 |
| Last admin demote/leave | Sole admin membership demoted/revoked | Validation error | — |

</frozen-after-approval>

## Code Map

- `app/models/user.rb` -- drop `belongs_to :company`, role enum, domain validation, last-admin guard; add memberships assocs, `super_admin` boolean
- `app/models/company_membership.rb` -- NEW: AASM state, Enumerize role, token, last-admin guard, invited_by
- `app/models/company.rb` -- `has_many :memberships`, `users through:`
- `app/controllers/concerns/auth_concern.rb` -- `current_membership`/`current_company` resolution + switch support
- `app/controllers/web/company/application_controller.rb`, `web/application_controller.rb` -- shared props, permissions from membership
- `app/policies/**` + `app/contexts/*` -- membership-based predicates (~15 sites catalogued in research §Baseline)
- `app/services/user_analytics_service.rb`, `user_agent_activity_service.rb`, `user_session_cost_token_usage_service.rb`, `web/profile_controller.rb` -- `company:` scoping
- `app/services/google_omni_auth_service.rb` -- auto-join policy rework
- `app/mailers/membership_mailer.rb`, `app/controllers/web/invitations_controller.rb`, `config/routes.rb` -- NEW invitation flow
- `app/controllers/web/company/members_controller.rb`, `app/frontend/shared/resources/members/MembersContent.tsx` -- invite w/ role, resend, revoke
- `app/resources/current_user_resource.rb`, `app/frontend/shared/ui/AppSidebar.tsx`, `app/frontend/pages/Profile/Show.tsx`, `app/frontend/pages/Invitations/*` -- FE contract, switcher, profile, invite pages
- `db/seeds.rb`, `test/factories/*`, `test/support/auth_helper.rb` -- memberships everywhere
- Peripheral: `app/channels/session_list_channel.rb`, `app/services/container_strategies/agent_session_strategy.rb`, `app/services/session_service.rb`, `api/v1/terminal_sessions_controller.rb` -- derive company from project/membership

## Tasks & Acceptance

**Execution:**
- [x] Setup: create worktree `.worktrees/multi-company` from `origin/develop`; symlink `node_modules`; verify container access
- [x] `db/migrate/*` -- create `company_memberships` + backfill from users (role/state mapping per research §Architectural) + add `users.super_admin` + drop `users.company_id/role/invited_by_id/invited_at`; verify legacy `project_id IS NULL` usage rows count first
- [x] `app/models/company_membership.rb` + `user.rb` + `company.rb` -- model layer per Code Map
- [x] `auth_concern.rb` + application controllers -- current_company/current_membership + `POST /company/switch`
- [x] Policies/contexts sweep -- all ~15 catalogued sites + grep-audit `\.company\b|company_id` for stragglers
- [x] #303 services + profile controller -- `company:` kwarg scoping
- [x] `google_omni_auth_service.rb` -- auto-join policy; invite-token passthrough via session
- [x] Invitations: mailer + views, `invitations_controller.rb`, routes, `Invitations/Show.tsx` (accept/signup/wrong-account variants)
- [x] Members page BE+FE -- invite with role picker, resend, revoke, `invited` badge
- [x] `current_user_resource.rb` + Typelizer regen + `AppSidebar.tsx` switcher + `Profile/Show.tsx` companies list
- [x] Peripheral sweep -- channel, container strategy, session_service, API controller
- [x] Tests: membership model, acceptance-matrix integration tests, switcher, cross-company isolation suite (extend `profile_usage_controller_test.rb` pattern), FE vitest for switcher/invite pages; adapt existing suite (factories, auth_helper)
- [x] `db/seeds.rb` -- second company + dual-membership demo user

**Acceptance Criteria:**
- Given a dual-membership user, when they open any page (projects, members, usage, sessions), then only current-company data is present, and after `POST /company/switch` the same pages show only the other company's data.
- Given an invited external (foreign-domain) email with role `admin`, when they accept and sign in, then they have admin permissions in the inviting company and no membership elsewhere.
- Given the full check suite, when `make check_all` runs in the worktree inside the container, then it is green.

## Design Notes

- Backfill mapping: `role: user.role (viewer→viewer, admin→admin, employee→employee)`, `state: user.state == "pending" ? "invited" : "active"`; super_admins get NO membership.
- Onboarding guards (`can_advance_to_authenticated?` etc.): replace `read_only?` with "all active memberships are viewer" (`viewer_everywhere?`).
- `permissions`/`projectPermissions` shared props computed from `current_membership` (admin/viewer), keeping existing prop names/shape where possible to minimize FE churn.
- Frontend forms: `zod4Resolver`; Typelizer regen after resource changes.

## Verification

**Commands:**
- `docker compose exec -T web bash -c "cd /app/.worktrees/multi-company && bin/rails db:migrate && bin/rails test"` -- expected: 0 failures
- `docker compose exec -T web bash -c "cd /app/.worktrees/multi-company && make check_all"` -- expected: all green (rails test, rubocop, brakeman, eslint, tsc, vitest)

**Manual checks (if no CLI):**
- letter_opener: invitation email renders with working token link in dev.

## Suggested Review Order

**Data model — the membership core**

- Join model owning per-company role+state, invitation tokens, last-admin guard — read this first
  [`company_membership.rb:25`](../../app/models/company_membership.rb#L25)

- Stateless invitation token embeds `[state, invited_at]` so accept/revoke/resend kills old links
  [`company_membership.rb:40`](../../app/models/company_membership.rb#L40)

- Backfill mapping (pending→invited, suspended→suspended, archived→revoked) + legacy pending unlock
  [`20260702000003_backfill_company_memberships.rb:11`](../../db/migrate/20260702000003_backfill_company_memberships.rb#L11)

**Company context resolution & switching**

- Session company id is never trusted — validated against active memberships on every request
  [`auth_concern.rb:98`](../../app/controllers/concerns/auth_concern.rb#L98)

- The switch endpoint: validate membership → write session → redirect (props re-scope on the visit)
  [`switch_controller.rb:7`](../../app/controllers/web/company/switch_controller.rb#L7)

- ActionCable resolves the same session-validated company at connect time
  [`connection.rb:9`](../../app/channels/application_cable/connection.rb#L9)

**Authorization — membership-based, fail-closed**

- API `read_only?` fails closed: no membership in the resolved company (or zero memberships) → no writes
  [`application_policy.rb:29`](../../app/policies/api/v1/application_policy.rb#L29)

- Owner/collaborator access now also requires an active membership in the project's company
  [`project.rb:86`](../../app/models/project.rb#L86)

**Invitations**

- Variant branching (expired/accept/wrong_account/login/signup) + token parking for auth round-trips
  [`invitations_controller.rb:14`](../../app/controllers/web/invitations_controller.rb#L14)

- Post-login continuation: lock-guarded accept only into the matching user, before the membership gate
  [`auth_concern.rb:79`](../../app/controllers/concerns/auth_concern.rb#L79)

- Domain auto-join demoted to OAuth policy: runs only when the user has zero memberships of any state
  [`google_omni_auth_service.rb:44`](../../app/services/google_omni_auth_service.rb#L44)

- Invite = find-or-create user + invited membership + mailer; resend/reinvite/duplicate branches
  [`members_controller.rb:20`](../../app/controllers/web/company/members_controller.rb#L20)

**Analytics isolation (#303 fix)**

- Usage services scope through `joins(:project)` — the current-company slice, legacy NULL-project rows excluded
  [`user_analytics_service.rb:55`](../../app/services/user_analytics_service.rb#L55)

**Frontend contract**

- `CurrentUser` now ships `currentCompany`/`currentRole`/`memberships` (Typelizer-generated)
  [`current_user_resource.rb:10`](../../app/resources/current_user_resource.rb#L10)

- Company switcher dropdown — renders only for multi-membership users, byte-identical otherwise
  [`AppSidebar.tsx:271`](../../app/frontend/shared/ui/AppSidebar.tsx#L271)

**Peripherals & proof**

- The isolation suite: dual-membership user must never see the other company's slice, on any screen
  [`cross_company_isolation_test.rb:8`](../../test/integration/web/cross_company_isolation_test.rb#L8)

## Deferred Work

Pre-existing or out-of-scope issues surfaced during the 2026-07-02 reviews. Not blockers.

- **Session-cookie last-writer-wins race on `current_company_id`** — a slow request started before `POST /company/switch` can commit its cookie after the switch response and revert it. Inherent to cookie sessions; would need server-side session store or a version guard. (Blind Hunter m1)

- **Last-admin concurrent race** — two admins demoting/revoking each other concurrently can leave a company with zero active admins; the guard is validation-only. Needs `company.with_lock` around admin-exit transitions or a DB-level constraint. (Edge Hunter #8)

- **Project-less (auth_setup) sessions have no home company** — currently fan out to every company where the user is an active member (list + broadcast aligned). Product decision pending: tag sessions with the company they were launched under (`terminal_sessions.company_id` hardening step from the research report) and scope to it. (Blind Hunter M5 residual)

- **Zero-downtime deploy story for the users-table contract** — old app instances selecting `users.role/company_id` during a rolling deploy will raise `UndefinedColumn` once migration 20260702000004 runs. Fine for single-instance deploys; revisit if rolling deploys arrive (`ignored_columns` two-step). (Blind Hunter M7 residual)

- **Admin "Activate" on an invited membership accepts on the invitee's behalf** — parity with the legacy manual-activation flow, but it bypasses the emailed-link ownership proof. Product decision whether to restrict to resend-only. (Blind Hunter m9 / Auditor F8a)
