---
research_type: technical
research_topic: "Restrict permissions: project deletion, company analytics, company sessions"
date: 2026-07-01
web_research_enabled: true
source_verification: true
stepsCompleted: [1, 2, 3, 4, 5, 6]
---

# Locking the Danger Zone: Technical Research — Restrict permissions: project deletion, company analytics, company sessions

## Executive Summary

This research validates and strengthens the planned tightening of three over-permissive Pundit policies in palad-app (`Web::Company::ProjectsPolicy#destroy?`, `Web::Company::AnalyticsPolicy#index?`, `Web::Company::SessionsPolicy`) against current industry practice for authorization hardening in multi-tenant SaaS. The internal design at `ai/research/technical-restrict-permissions-pundit-policies-2026-07-01.md` is sound; web evidence reinforces every core choice and resolves the three open product decisions.

**Key findings**

1. **The planned direction matches industry norms.** Mature platforms (GitHub, Vercel, Notion, Google Workspace) gate workspace/repository deletion behind owner-or-admin roles, and gate org-wide analytics/audit views behind admin roles. Restricting project deletion to `owner || company-admin` and analytics/sessions to `admin?` is exactly the prevailing pattern. ([GitHub repo deletion](https://docs.github.com/en/repositories/creating-and-managing-repositories/deleting-a-repository), [Vercel RBAC](https://vercel.com/docs/rbac/access-roles), [Notion roles](https://www.notion.com/help/whos-who-in-a-workspace))
2. **The bug being fixed is the #1 web-security risk.** Letting a non-owner collaborator delete a project, or any member view company-wide analytics/sessions, is a textbook **Broken Access Control / BOLA** failure — OWASP A01:2021 (web) and API1:2023 (API), the top risk in both lists. The fix is squarely a security fix, not just a UX nicety. ([OWASP A01:2021](https://owasp.org/Top10/2021/A01_2021-Broken_Access_Control/), [OWASP API1:2023](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/))
3. **403 vs 302 is a content-negotiation decision, and Inertia supports both.** The HTTP-correct status for an authenticated-but-forbidden user is **403 Forbidden** (not 401, not a silent 302). Best practice is to map `Pundit::NotAuthorizedError` to 403 globally via `config.action_dispatch.rescue_responses`, while keeping a friendly redirect+flash for ordinary HTML navigation if desired. Inertia can render a 403 as either a redirect-with-flash or a dedicated error page. ([Matt Brictson](https://mattbrictson.com/blog/handling-rails-exceptions), [Pundit #412](https://github.com/varvet/pundit/issues/412), [Inertia error handling](https://inertiajs.com/error-handling))
4. **UI hiding is UX, never security.** Hiding the Delete button / nav links is correct *as defense-in-depth and good UX*, but the server policy must remain the sole enforcement point — every authority is unanimous that client-side hiding offers zero protection. ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html), [Indusface](https://www.indusface.com/learning/broken-access-control/))
5. **Authorization needs its own test surface.** Industry practice is a deliberate **roles × actions matrix** tested at the policy level (fast unit specs) *plus* request specs for the cross-tenant/forbidden paths — exactly the test plan the internal design already proposes. ([pundit-matchers](https://github.com/pundit-community/pundit-matchers), [Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/))

**Top actionable recommendations**

- **Ship the three-policy tightening as designed** (`owner || admin` for delete; `admin?` for analytics/sessions index/show/new). High confidence — it matches GitHub/Vercel/Notion and OWASP least-privilege/deny-by-default.
- **Resolve the 403-vs-302 blocker by adopting 403 as the canonical status** via `rescue_responses["Pundit::NotAuthorizedError"] = :forbidden`, then render a friendly Inertia experience on top (redirect+flash for HTML, JSON 403 for API). This satisfies the AC's literal "403" *and* keeps UX friendly. Medium-high confidence.
- **Keep super-admins out of the company gates** (`current_user.admin?` only). They are already redirected to the admin panel; adding `|| super_admin?` is dead code and weakens least-privilege/separation-of-duties. Medium-high confidence.
- **"Restrict permissions" = button-level for delete, page-level for analytics/sessions.** Hide the Delete button (page stays viewable) but treat analytics/sessions as admin-only *pages*. This mirrors how GitHub/Notion/Vercel scope a single destructive control vs. an entire admin surface. High confidence.
- **Add `after_action :verify_authorized` (dev/test only) and policy unit specs** to prevent regressions where a future controller forgets to authorize. High confidence.

---

## Table of Contents

1. Problem Framing & Research Methodology
2. Industry Precedents
3. Patterns & Pitfalls
4. Concrete Libraries & Approaches
5. Recommendations for palad-app
6. Open Decisions Informed by Research
7. Sources & Confidence

---

## 1. Problem Framing & Research Methodology

### What we are building

Ticket #211 tightens three Pundit policies in palad-app's company namespace that are currently too permissive (verified against the live code):

- **G1 — Project deletion.** `Web::Company::ProjectsPolicy#destroy?` (`app/policies/web/company/projects_policy.rb:18-20`) authorizes any user who `accessible_by?` the project, which includes plain collaborators. A non-owner collaborator can delete a project. The fix: restrict to project owner (`Project#admin?`, owner-only) **or** company admin (`current_user.admin?`).
- **G2 — Company analytics.** `Web::Company::AnalyticsPolicy#index?` is hardcoded `true` (`analytics_policy.rb:6`). Any authenticated member sees company-wide cost/token analytics. Fix: `current_user.admin?`.
- **G3 — Company sessions.** `Web::Company::SessionsPolicy` returns `true` for `index?`, `new?`, `show?` (`sessions_policy.rb:6-8`). Any member can list/view every session in the company. Fix: `current_user.admin?` on all three.

The pattern to mirror already exists in the codebase: `Web::Company::MembersPolicy` uses `current_user.admin?` plus a `same_company?` guard (`app/policies/web/company/members_policy.rb:10-19`). The role model is `User#role` enumerized as `%i[employee admin super_admin]`, and super-admins are redirected to the admin panel before they ever reach company routes.

### Why research it

Three product decisions in the internal design are unresolved and block clean implementation:

1. The AC literally say a denied user "receives 403," but the web layer currently performs a **302 redirect + flash** (`Web::Company::ApplicationController#user_not_authorized`); only the API layer returns 403. These are mutually contradictory as written.
2. Whether `super_admin` should also pass the admin gates.
3. Whether "restrict permissions" means button-level (hide Delete) or page-level (block the whole settings/analytics page).

This is an authorization-hardening change, so getting the *pattern* right matters more than the three one-liners. We need external evidence that (a) the role boundary is correct, (b) the denial signal is HTTP-correct, and (c) the test strategy is comprehensive.

### How it was researched

Mandatory web research using WebSearch + WebFetch against primary/authoritative sources: OWASP (Authorization Cheat Sheet, Top 10 A01:2021, API Security Top 10 API1:2023), vendor docs (GitHub, Vercel, Notion, Google Workspace, Microsoft Entra/Learn), library docs and maintainer discussions (Pundit README + issues, palkan/action_policy, pundit-matchers, Inertia.js docs), and engineering write-ups (Saeloun, Matt Brictson, thoughtbot, ShakaCode). Claims carry inline source URLs and confidence levels; conflicts are noted in §7. Queries used are listed in §7.

---

## 2. Industry Precedents

How mature platforms scope destructive/irreversible actions and gate org-level analytics/audit views.

### 2.1 Destructive action = owner/admin only, with typed confirmation (GitHub)

GitHub is the canonical reference for a project-stack audience. Repository deletion is restricted and uses a **typed-confirmation "Danger Zone"**:

- The GitHub docs state: "You can delete any repository or fork if you're either an organization owner or have admin permissions for the repository or fork." For personal repos, only the owner can delete. ([GitHub: Deleting a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/deleting-a-repository))
- In practice, the destructive control (the "Danger Zone" Delete option) is **not surfaced** to users who lack delete permission — a non-owner collaborator does not see the option. This is observed product behavior rather than a verbatim docs statement; GitHub's own docs only document the steps for permitted users and do not describe the hidden-control behavior. A community thread describes it informally: org owners can be "disabling the delete option for non-owners even if they're Admins." ([GitHub community discussion #175250](https://github.com/orgs/community/discussions/175250))
- Deletion requires **typed confirmation**: the docs say "To verify that you're deleting the correct repository, in the text box, type the name of the repository you want to delete." ([GitHub: Deleting a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/deleting-a-repository))
- Organizations can further **restrict admins**: the org setting "Allow members to delete or transfer repositories for this organization," when disabled, leaves deletion to **org owners only**, even for repo admins. ([GitHub: Setting permissions for deleting or transferring repositories](https://docs.github.com/en/organizations/managing-organization-settings/setting-permissions-for-deleting-or-transferring-repositories))

**Takeaways for #211:** (a) destructive action gated to owner/admin is the norm; (b) the destructive control is **hidden** for non-permitted users (button/section-level hiding), not the entire repo; (c) typed confirmation is a widely-adopted extra guardrail (a candidate enhancement, not in #211 scope).

### 2.2 Owner-reserved deletion and graded roles (Vercel, Notion)

- **Vercel** has multiple graded team-level roles — the current docs list eight (Owner, Member, Developer, Security, Billing, Pro Viewer, Enterprise Viewer, Contributor) plus three project-level roles (Project Administrator, Project Developer, Project Viewer) — including read-only Viewer roles and an Owner role with exclusive role-management authority. The docs state: "role changes, including assignment and revocation of team member roles, are an exclusive capability of those with the owner role," and "we recommend that at least two individuals have owner permissions" for continuity. (Note: the docs recommend multiple owners but do **not** document a hard "cannot remove the last owner" rule.) ([Vercel: Access Roles](https://vercel.com/docs/rbac/access-roles), [Vercel: Managing Team Members](https://vercel.com/docs/rbac/managing-team-members))
- **Notion**: only **Workspace Owners** can delete a workspace; "Membership admins" (Enterprise) can add/remove members but **cannot** change workspace settings or delete the workspace; regular members/guests cannot. ([Notion: Who's who in a workspace](https://www.notion.com/help/whos-who-in-a-workspace))

**Takeaway:** the most destructive action (deleting the container) is reserved for the **highest** role; "admin"-ish middle roles often manage members but not the nuclear button. palad-app's choice — delete allowed for project **owner** or **company admin** — is slightly more permissive than "owner only," but it matches GitHub's "org owner OR repo admin" model and is reasonable for a project (not a whole company). (Medium confidence on the exact boundary — it is a product call, see §6.)

### 2.3 Org-level analytics/audit gated to admins (Google Workspace, Vercel, GitHub)

- Org-wide **audit logs / admin-initiated action logs** are an admin surface in Google Workspace; security tooling treats the audit/usage views as privileged. ([NinjaOne: Track admin-initiated deletes with SaaS logs](https://www.ninjaone.com/blog/use-saas-logs-to-monitor-initiated-deletions/), [Elastic: Google Workspace admin role detection](https://www.elastic.co/guide/en/security/current/google-workspace-admin-role-deletion.html))
- Best-practice guidance: **admin rights reserved for a small group**, used only when necessary, with dedicated admin accounts separate from day-to-day user accounts. ([Google Workspace admin guidance, via SysCloud](https://www.syscloud.com/saas-data-protection-center/google-workspace/delete-a-user-from-google-workspace/), [AppOmni: User roles & least privilege](https://appomni.com/learn/saas-security-fundamentals/user-roles-and-least-privilege-in-saas-apps/))
- Vercel's read-only **Viewer** roles (Pro Viewer, Enterprise Viewer) and the **Billing** role exist precisely so that read access to dashboards/usage can be granted without write/admin power — e.g., the Billing role gets "read-only access to every project" and Enterprise Viewer gets "comprehensive read-only access." Visibility is itself a graded permission, not a free-for-all. ([Vercel: Access Roles](https://vercel.com/docs/rbac/access-roles))

**Takeaway:** company-wide analytics (cost/token usage) and the cross-project session list are exactly the kind of aggregate/audit surface that platforms gate behind admin. Restricting them to `admin?` is mainstream.

### 2.4 Soft delete + grace period as the dominant deletion mechanic

Across SaaS, irreversible deletion is increasingly implemented as **soft delete + grace period** (a "trash" window, commonly 30/90 days) before a background job hard-deletes — balancing undo/recovery against GDPR/CCPA "right to erasure." ([dev.to: soft vs hard delete](https://dev.to/akarshan/the-delete-button-dilemma-when-to-soft-delete-vs-hard-delete-3a0i), [koder.ai](https://koder.ai/blog/soft-deletes-vs-hard-deletes), [Microsoft Entra: recover from deletions](https://learn.microsoft.com/en-us/entra/architecture/recover-from-deletions)). Implementation guidance: use a `deleted_at` timestamp rather than a boolean, and ensure every query path respects the deleted state. ([Medium: soft/hard delete best practices](https://surajsinghbisht054.medium.com/understanding-soft-delete-and-hard-delete-in-software-development-best-practices-and-importance-539a935d71b5))

**Takeaway / scope note:** #211 only changes *who* may delete, not *how* deletion works (palad-app does a hard `project.destroy!`). Soft-delete is **out of scope** for #211 but is a strong follow-up given that project deletion is irreversible — flagged in §5.

### 2.5 Two-person / four-eyes rule (for the most sensitive actions)

For the highest-risk operations, regulated and security-sensitive systems use a **two-person rule / four-eyes principle** (dual approval). It's standard in finance/DevOps for irreversible or high-blast-radius actions. ([Graph AI: four-eyes principle](https://www.graphapp.ai/engineering-glossary/devops/four-eyes-principle), [Flagsmith: four-eyes for flag changes](https://www.flagsmith.com/blog/what-is-the-four-eyes-principle), [Wikipedia: Two-person rule](https://en.wikipedia.org/wiki/Four_eyes_principle)). This is **overkill for #211** (single-tenant project delete) but worth noting as the top of the guardrail spectrum if palad-app ever adds company-deletion or bulk-destructive operations.

---

## 3. Patterns & Pitfalls

### 3.1 The two non-negotiables: deny-by-default and least-privilege

OWASP's Authorization Cheat Sheet codifies the principles this ticket embodies ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)):

- **Enforce least privilege** — grant only the minimum needed; periodically review for "privilege creep."
- **Deny by default** — "the application must always make a decision… to either deny or permit"; deny unless explicitly permitted.
- **Validate permissions on every request** — use a global mechanism (filters/middleware), because "even if just a single access control check is 'missed', the confidentiality and/or integrity of a resource can be jeopardized."
- **Server-side enforcement** — "developers must never rely on client-side access control checks"; client checks are for UX only.
- **Handle failures securely** — centralize failure handling; don't leak sensitive info; don't leave the app in an unstable state.

palad-app's `before_action :dynamic_authorize!` is precisely the "global, application-wide mechanism" OWASP recommends, and the three policies as currently written (`true` / `accessible_by?`) are textbook violations of deny-by-default/least-privilege.

### 3.2 The pitfall being fixed is OWASP #1: Broken Access Control / BOLA

- **OWASP A01:2021 Broken Access Control** is the #1 web risk; "94% of tested applications" were affected. A named example failure is "violation of the principle of least privilege or deny by default… available to anyone," and "accessing API with missing access controls for POST, PUT and DELETE." Prevention: "Deny by default… enforce server-side, centralize the rules, and apply the principle of least privilege." ([OWASP A01:2021](https://owasp.org/Top10/2021/A01_2021-Broken_Access_Control/))
- **OWASP API1:2023 Broken Object Level Authorization (BOLA / IDOR)** is the #1 API risk: APIs that authenticate but don't verify the caller may act on *this specific object*. Prevention: "never trusting client-supplied object IDs without server-side checks… validate object ownership on every request." ([OWASP API1:2023](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/))

G1 (collaborator deletes a project they don't own) is a near-perfect BOLA instance: the controller `find`s a project the user can reach and acts on it without verifying ownership. The fix re-introduces the per-object ownership check (`current_project.admin?(current_user)`).

### 3.3 Privilege-escalation traps to avoid in the implementation

From the privilege-escalation literature ([Frontegg](https://frontegg.com/blog/privilege-escalation), [Cynet](https://www.cynet.com/network-attacks/privilege-escalation/), [BeyondTrust](https://www.beyondtrust.com/blog/entry/privilege-escalation-attack-defense-explained)) and OWASP:

- **Blanket/convenience permissions** ("hardcode `true` to ship faster") are the exact anti-pattern that created G1–G3. ([Arctic Wolf](https://arcticwolf.com/resources/glossary/privilege-escalation/))
- **Horizontal escalation across tenants.** In a multi-tenant app, the dangerous case is user-of-company-A acting on company-B's object. palad-app's `current_project` is scoped to `current_user.company.projects` (`projects_policy.rb:27`), so a cross-company id resolves to `nil` → denied. **Keep that scoping** — it is the primary tenant-isolation guard. ([OWASP A01:2021](https://owasp.org/Top10/2021/A01_2021-Broken_Access_Control/))
- **Forgotten authorize calls.** The most common Pundit regression is a new controller/action that simply forgets to authorize. Mitigate with `after_action :verify_authorized` (and `verify_policy_scoped` for index) — a dev/test failsafe that raises if `authorize`/`policy_scope` was never called. ([Pundit README via RubyDoc](https://www.rubydoc.info/gems/pundit), [thoughtbot](https://thoughtbot.com/blog/a-javascript-developer-s-guide-to-rails-authorization-with-pundit)). Note Pundit's own docs stress this is a *development aid, not a failsafe* — removing it must not change behavior. palad-app's `dynamic_authorize!` before_action partly covers this, but `verify_authorized` catches the case where a future controller bypasses the concern.
- **Privilege creep** — periodically re-audit who can do what. ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html))

### 3.4 Denial signaling: 403 vs 401 vs 302 (the core decision)

- **403, not 401.** An authenticated user who lacks permission must get **403 Forbidden**; **401** means "not authenticated." Mapping authorization failures to 401 wrongly can trigger auto-logout. This is explicitly raised against Pundit's default. ([Pundit issue #412](https://github.com/varvet/pundit/issues/412), [Pundit issue #503](https://github.com/varvet/pundit/issues/503))
- **A silent 302 redirect is a UX convention, not an HTTP-correct status.** It's common and friendly for HTML apps, but it does not satisfy an AC that says "receives 403," and it can hide failures from API/test clients. ([Matt Brictson: Rails exception handling](https://mattbrictson.com/blog/handling-rails-exceptions))
- **Recommended Rails idiom: `rescue_responses`.** Add `config.action_dispatch.rescue_responses["Pundit::NotAuthorizedError"] = :forbidden` so Rails returns a real **403** and automatically content-negotiates (HTML 403 page vs JSON for API clients), without per-controller `rescue_from`. ([Matt Brictson](https://mattbrictson.com/blog/handling-rails-exceptions))
- **`rescue_from` with `respond_to` for custom logic.** If you want 403-JSON for API and redirect+flash for HTML, a `rescue_from Pundit::NotAuthorizedError` with a `respond_to` block gives full control. ([oneuptime: Pundit authorization](https://oneuptime.com/blog/post/2025-07-02-rails-pundit-authorization/view), [Pundit README](https://github.com/varvet/pundit/blob/main/README.md))
- **Cross-tenant reads: prefer 404 over 403** to avoid leaking existence. For reads where even acknowledging the object exists is a leak, return **404** (object not in the authorized scope) rather than 403. ([Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/)). For palad-app, `current_project` returning `nil` for a foreign id already yields a denial — fine to keep, and conceptually closer to "not found."

### 3.5 Inertia-specific denial handling

Inertia adds a wrinkle: an Inertia visit expects an Inertia response. Two supported patterns ([Inertia: Authorization](https://inertia-rails.dev/guide/authorization), [Inertia: Error handling](https://inertiajs.com/error-handling)):

1. **Pass permission flags as props** (the recommended primary approach): expose a `can: { delete_project: ... }` object so the page conditionally renders controls. This is the UX/visibility layer — *not* the enforcement layer. This is exactly what the internal design's `can_delete` prop does. **Caveat:** the official Inertia-Rails example builds this `can` object using **Action Policy's** `allowed_to?` helper (the guide explicitly says it uses "the Action Policy gem"), not a Pundit helper — so don't copy-paste `allowed_to?` expecting it to work under bare Pundit. palad-app builds the `can` object manually (e.g. `current_project.admin?(current_user)`), which is the correct equivalent on Pundit and needs no Action Policy helper. ([Inertia Rails: Authorization](https://inertia-rails.dev/guide/authorization))
2. **Render an error page / redirect on denial.** In production you register an exception handler that, for statuses like 403/404/500, renders a dedicated Inertia error page with the status as a prop (or, for a softer UX, redirect back with a flash). In development Inertia shows non-Inertia responses (like a raw 403) in a modal. ([Inertia: Error handling](https://inertiajs.com/error-handling))

So returning a real 403 and rendering it as a friendly Inertia error page (or redirect+flash) is fully supported — palad-app does **not** have to choose between "403" and "friendly UX."

### 3.6 UI hiding is UX, never a control

Every authority is unanimous: hiding/disabling buttons is bypassable and provides **no** protection. "Access control decisions must always be enforced on the server… even if a user can see a 'Delete' button, the server should block the request if they lack admin rights." ([Indusface: Broken Access Control](https://www.indusface.com/learning/broken-access-control/)). For the *UX* choice between hiding vs disabling: **hide** controls that are gated by permission (vs. disable, which signals "exists but temporarily unavailable"). ([Smart Interface Design Patterns: hidden vs disabled](https://smart-interface-design-patterns.com/articles/hidden-vs-disabled/), [UX Psychology](https://uxpsychology.substack.com/p/hidden-vs-disabled-states)). This validates the internal design's "hide the Delete button, but the policy is authoritative."

### 3.7 Testing patterns for authorization

- **Roles × actions matrix as policy unit specs.** Pundit policies are plain Ruby objects, so test them directly with one `context` per user type. `pundit-matchers` (≥2.1) recommends `permit_only_actions(%i[...])` to **allow-list** permitted actions, so an over-permissive policy (an action that *shouldn't* be allowed slipping through) fails the test. ([pundit-matchers](https://github.com/pundit-community/pundit-matchers), [Thunderbolt Labs](https://www.thunderboltlabs.com/blog/2013/03/27/testing-pundit-policies-with-rspec/))
- **Request specs for the cross-tenant/forbidden path.** Saeloun's most-emphasized test is the *negative*: an "another-account" user must be denied (404/403), not just that the policy returns false in isolation. ([Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/))
- **Front-end gating tests** (Vitest/jsdom) for the hide-the-button/nav behavior — visibility only, with the server as truth.

palad-app uses Minitest (not RSpec); the matrix-of-roles-×-actions concept maps directly to plain Minitest policy tests instantiating the policy with a `BaseContext`, which the internal design already specifies. `pundit-matchers` is RSpec-only, so it is a *conceptual* reference here, not a drop-in dependency.

---

## 4. Concrete Libraries & Approaches (Rails + Pundit + React/Inertia/Mantine)

### 4.1 Stay on Pundit (don't switch gems for #211)

Comparisons consistently land on: **Pundit** = minimal, explicit, plain-Ruby policy objects, smallest API, easiest to test/review; **CanCanCan** = centralized `Ability` class, good for RESTful CRUD; **Action Policy** = a fuller framework adding failure *reasons*, policy aliases, scoping, and per-request caching of expensive checks. ([Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/), [palkan/action_policy discussion #1](https://github.com/palkan/action_policy/discussions/1), [Pundit README](https://github.com/varvet/pundit))

- palkan (Action Policy author): "Pundit is pretty much just a helper for your controller… Action Policy is full-featured framework." ([action_policy discussion #1](https://github.com/palkan/action_policy/discussions/1))
- "The default recommendation for a serious Rails product is Pundit: explicit, review-friendly, and small enough that the team will actually read the policies." ([Saeloun summary via search](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/))

**Recommendation:** palad-app already runs Pundit with a namespaced policy convention (`Web::Company::*Policy`) and a custom `dynamic_authorize!`. #211 needs nothing Action Policy provides (no failure-reasons UI, no expensive cached checks). Switching gems would be unjustified scope. **Stay on Pundit.** (High confidence.) Note that the official Inertia-Rails authorization guide demonstrates the `can`-flags-as-props pattern with **Action Policy's** `allowed_to?` helper, not Pundit — so the recommended *pattern* (build a `can` object and pass it as props) is library-agnostic, but the official sample code is Action Policy-specific. palad-app builds the same `can` object manually under Pundit (its `can_delete` prop), which is the correct Pundit equivalent and needs no `allowed_to?`. ([Inertia Rails: Authorization](https://inertia-rails.dev/guide/authorization))

### 4.2 Concrete techniques to apply

1. **Tighten the three policies** to `owner || admin` / `admin?` (deny-by-default), mirroring `MembersPolicy`. (The actual fix.)
2. **Map `NotAuthorizedError` → 403** via `config.action_dispatch.rescue_responses["Pundit::NotAuthorizedError"] = :forbidden` *or* a `rescue_from` with `respond_to` (HTML redirect+flash, JSON/Inertia 403). Resolves the AC's "403." ([Matt Brictson](https://mattbrictson.com/blog/handling-rails-exceptions), [oneuptime](https://oneuptime.com/blog/post/2025-07-02-rails-pundit-authorization/view))
3. **Expose permission flags as Inertia props** (`can_delete`, `permissions.isAdmin`) for visibility-layer hiding — already the design. ([Inertia: Authorization](https://inertia-rails.dev/guide/authorization))
4. **Add the dev/test failsafe** `after_action :verify_authorized` (+ `verify_policy_scoped` for index) to catch forgotten authorizations in future controllers. ([Pundit README](https://www.rubydoc.info/gems/pundit))
5. **Policy unit tests as a roles × actions matrix** + request specs for the forbidden/cross-tenant path (Minitest analog of pundit-matchers' allow-list discipline). ([pundit-matchers](https://github.com/pundit-community/pundit-matchers), [Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/))

### 4.3 Role modeling: enum is fine; don't add rolify

- For a **fixed, small set of mutually-exclusive roles** (employee/admin/super_admin), an **enum/enumerize column** is the simplest correct model. ([Codersations: role-based auth with Rails enum](https://gustavocguimaraes.wordpress.com/2014/12/17/role-based-authorization-with-rails-4-enum/comment-page-1/), [RailsApps: Rails authorization](https://railsapps.github.io/rails-authorization.html))
- **rolify** adds two tables (`roles`, `users_roles`) and resource-scoped roles — powerful but overkill unless a user needs *multiple* roles or *per-resource* roles. ([rolify](https://github.com/RolifyCommunity/rolify), [RailsApps](https://railsapps.github.io/rails-authorization.html))

palad-app already uses `enumerize ... in: %i[employee admin super_admin]`. **Keep it.** Project-level "ownership" is correctly modeled as a relationship (`Project#owner_id`/`admin?`), not a global role — i.e., palad-app already blends RBAC (company role) with ReBAC (project ownership), which is exactly what OWASP recommends as you outgrow pure RBAC. ([OWASP Authorization Cheat Sheet — prefer ABAC/ReBAC](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html))

**Super-admin modeling:** the common pattern is to keep super-admins in a **separate namespace/area** (an admin panel) rather than threading `super_admin?` checks through tenant-facing policies — which is precisely what palad-app does via `redirect_super_admin_to_admin_panel`. This is the "dedicated admin account / separation of duties" pattern from Google Workspace guidance. ([SysCloud / Google Workspace admin guidance](https://www.syscloud.com/saas-data-protection-center/google-workspace/delete-a-user-from-google-workspace/))

---

## 5. Recommendations for palad-app

Tied directly to the internal design (`ai/research/technical-restrict-permissions-pundit-policies-2026-07-01.md`):

1. **Ship the three-policy tightening exactly as designed.** `destroy? = current_project.admin?(current_user) || current_user.admin?`; `AnalyticsPolicy#index? = current_user.admin?`; `SessionsPolicy#{index?,new?,show?} = current_user.admin?`. This is deny-by-default + least-privilege and matches GitHub/Vercel/Notion. (High confidence.)
2. **Adopt 403 as the canonical denial status**, satisfying the AC literally while keeping UX friendly. Use `rescue_responses["Pundit::NotAuthorizedError"] = :forbidden` (global, content-negotiated) or a `rescue_from` with `respond_to` (HTML → redirect+flash *or* Inertia error page; API → JSON 403). See §6.1 for the recommended exact behavior. (Medium-high.)
3. **Keep the gates `current_user.admin?` only — no `|| super_admin?`.** Super-admins are already redirected out of the company area; adding the clause is dead code and dilutes separation-of-duties. (Medium-high.) See §6.2.
4. **Button-level hide for Delete; page-level admin gate for analytics/sessions.** Hide the Settings "Danger Zone" Delete button via the `can_delete` prop (page stays viewable to collaborators), but treat company analytics & sessions as admin-only *pages* (nav items `adminOnly: true`; policy denies the route). This mirrors GitHub (hide the destructive control) vs. Vercel/Notion (admin-only surfaces). (High confidence.) See §6.3.
5. **Add `after_action :verify_authorized`/`verify_policy_scoped` in dev+test** to prevent future forgotten-authorize regressions; document it as a dev aid, not a failsafe. (High confidence.)
6. **Add policy unit specs (roles × actions matrix) + request specs for the forbidden path** as the design specifies; the request spec must assert the *new* denial behavior chosen in §6.1, and must guard against false-greens from the onboarding redirect. (High confidence.)
7. **Follow-ups (out of #211 scope, recommend tickets):** (a) **typed-confirmation** on project delete (type the project name) — GitHub-style guardrail for an irreversible action; (b) **soft-delete + grace period** for projects given deletion is irreversible and currently a hard `destroy!`; (c) re-audit the remaining company/project policies for other `true`/`accessible_by?` over-grants (periodic privilege-creep review). (Medium confidence; clearly separate work.)

---

## 6. Open Decisions Informed by Research

### 6.1 — 403 vs 302 redirect for denied web (HTML/Inertia) actions

**Decision:** Adopt **403 as the canonical status**, rendered through a friendly Inertia experience. Concretely: map `Pundit::NotAuthorizedError` to `:forbidden` (via `config.action_dispatch.rescue_responses` or a `rescue_from`), and on the Inertia/HTML path render either a dedicated 403 error page or a redirect-back-with-flash carrying a 403 — while API requests get a JSON 403. This satisfies the AC's literal "403" without sacrificing the friendly redirect+alert UX the app has today.

**Why:** 403 is the HTTP-correct status for "authenticated but forbidden" (401 is for unauthenticated, and would wrongly imply logout) ([Pundit #412](https://github.com/varvet/pundit/issues/412)). A silent 302 is a UX convention, not a status, and cannot satisfy a "receives 403" AC ([Matt Brictson](https://mattbrictson.com/blog/handling-rails-exceptions)). Inertia explicitly supports rendering error responses (incl. 403) as error pages, and content-negotiation lets HTML and API diverge cleanly ([Inertia: error handling](https://inertiajs.com/error-handling), [oneuptime](https://oneuptime.com/blog/post/2025-07-02-rails-pundit-authorization/view)). The internal design's "Option (b)" (return 403) is the industry-correct one; the only cost it flagged — blast radius across all company policy failures — is real, so pair it with a regression sweep of other company controllers and keep a friendly rendered page so users still see an alert rather than a raw error.

**Nuance:** For pure cross-tenant *reads* where even confirming existence leaks information, **404** is preferable to 403 ([Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/)). palad-app's `current_project` already resolves foreign ids to `nil`/denial, so this is largely handled; just don't echo "this project exists but you can't touch it" for cross-company ids.

**Confidence:** Medium-high. The HTTP semantics (403) are unambiguous; the only judgment call is the rendering style (error page vs redirect-with-flash), which is a UX preference. If product instead wants minimal scope, the fallback is the internal design's "Option (a)" (keep 302+alert and amend the AC wording away from "403") — but that contradicts the AC as written, so 403 is the better resolution.

### 6.2 — Should super_admins also pass these admin gates?

**Decision:** **No.** Keep the gates `current_user.admin?` only. Do not add `|| current_user.super_admin?`.

**Why:** (1) In palad-app, super-admins are redirected to the admin panel before reaching company routes (`redirect_super_admin_to_admin_panel`), so the clause is dead code today. (2) The industry pattern is **separation of duties / dedicated admin surfaces**: super-admin power lives in its own area, not threaded through tenant-facing policies — Google Workspace explicitly advises performing admin tasks in a dedicated admin account separate from user-facing work ([SysCloud / Google Workspace](https://www.syscloud.com/saas-data-protection-center/google-workspace/delete-a-user-from-google-workspace/), [AppOmni](https://appomni.com/learn/saas-security-fundamentals/user-roles-and-least-privilege-in-saas-apps/)). (3) Least-privilege/deny-by-default argue against widening a gate "just in case" ([OWASP A01:2021](https://owasp.org/Top10/2021/A01_2021-Broken_Access_Control/), [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)). If product later wants super-admins to operate inside the company UI, that is a deliberate, separate change (lifting the redirect for specific paths), not an `|| super_admin?` clause sprinkled into three policies.

**Confidence:** Medium-high. Contingent on the current `redirect_super_admin_to_admin_panel` behavior remaining true; if that redirect is ever removed, revisit.

### 6.3 — Button-level (hide delete) vs page-level (block the whole settings/analytics page)

**Decision:** **Mixed, by surface:**
- **Project deletion (G1): button-level.** Hide the "Danger Zone" Delete button for non-owner/non-admin (via the `can_delete` prop); the Settings page itself stays viewable to collaborators. This matches GitHub, where the destructive Delete control is not surfaced to users without delete rights while the repo remains usable (observed behavior; described informally in [GitHub community discussion #175250](https://github.com/orgs/community/discussions/175250) as "disabling the delete option for non-owners"), and the "hide controls gated by permission" UX guidance ([Smart Interface Design Patterns](https://smart-interface-design-patterns.com/articles/hidden-vs-disabled/)).
- **Company analytics & sessions (G2/G3): page-level.** These are admin-only *surfaces* (aggregate cost/usage analytics; cross-project session/audit list). Gate the whole page (policy denies the route; nav item `adminOnly`). This matches how Vercel/Google Workspace/GitHub gate org-wide dashboards and audit views behind admin ([Vercel: Access Roles](https://vercel.com/docs/rbac/access-roles), [NinjaOne](https://www.ninjaone.com/blog/use-saas-logs-to-monitor-initiated-deletions/)).

**Rule of thumb from the evidence:** hide the *individual destructive control* when the surrounding page still has legitimate read value for the user (project settings), but gate the *entire page* when the page's whole purpose is privileged data (company analytics/audit). In **all** cases the server policy is the enforcement point; hiding is UX/defense-in-depth only ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html), [Indusface](https://www.indusface.com/learning/broken-access-control/)).

**Open sub-question for product:** whether collaborators should even *see* the project Settings page (which exposes owner email, member list, counts). #211 as designed leaves Settings viewable and only hides Delete. If product considers that metadata sensitive, gating `SettingsPolicy#show?` is a separate, larger change. The research does not force this either way — it's a data-sensitivity product call; just keep it consistent with least-privilege.

**Confidence:** High for the split itself (button-level delete, page-level analytics/sessions); Medium for the Settings-page-visibility sub-question (product/data-sensitivity dependent).

---

## 7. Sources & Confidence

### Primary / authoritative sources

1. OWASP Authorization Cheat Sheet — deny-by-default, least privilege, validate every request, server-side enforcement, prefer ABAC/ReBAC. **High.** https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html
2. OWASP Top 10 A01:2021 Broken Access Control — #1 web risk; prevention = deny by default + server-side + least privilege. **High.** https://owasp.org/Top10/2021/A01_2021-Broken_Access_Control/
3. OWASP API Security Top 10 API1:2023 Broken Object Level Authorization (BOLA/IDOR) — #1 API risk; validate object ownership every request. **High.** https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/
4. GitHub Docs — Deleting a repository (delete allowed for organization owner or repo admin; typed-name confirmation required). The docs do **not** document hidden-control behavior or a name-match button-disable; those are observed UI behavior, not docs quotes. **High** (for the documented owner/admin + typed-confirmation facts). https://docs.github.com/en/repositories/creating-and-managing-repositories/deleting-a-repository
5. GitHub Docs — Setting permissions for deleting or transferring repositories (restrict admins → owners only). **High.** https://docs.github.com/en/organizations/managing-organization-settings/setting-permissions-for-deleting-or-transferring-repositories
6. Vercel Docs — Access Roles / Managing Team Members (multiple graded team-level roles incl. read-only Viewer roles; role assignment/revocation exclusive to Owners; recommends ≥2 owners for continuity; owners delete members and you may remove yourself). Note: docs do **not** state a "cannot remove the last Owner" rule. **High.** https://vercel.com/docs/rbac/access-roles , https://vercel.com/docs/rbac/managing-team-members
7. Notion Help — Who's who in a workspace (only Workspace Owners delete a workspace; Enterprise "membership admins" can add/remove members but cannot change workspace settings or delete). Note: page does **not** document a last-owner-cannot-leave rule. **High.** https://www.notion.com/help/whos-who-in-a-workspace
8. Pundit README + RubyDoc (varvet/pundit) — policy objects, `verify_authorized`/`verify_policy_scoped` dev aid, `rescue_from NotAuthorizedError`. **High.** https://github.com/varvet/pundit , https://github.com/varvet/pundit/blob/main/README.md , https://www.rubydoc.info/gems/pundit
9. Pundit issue #412 — NotAuthorizedError should be 403, not 401. **High.** https://github.com/varvet/pundit/issues/412
10. Pundit issue #503 — flexibility of NotAuthorizedError keys (context). **Medium.** https://github.com/varvet/pundit/issues/503
11. palkan/action_policy discussion #1 — Action Policy (framework) vs Pundit (controller helper); context injection, scopes, failure reasons. **High.** https://github.com/palkan/action_policy/discussions/1
12. Inertia Rails — Authorization (pass `can` flags as props). **High.** https://inertia-rails.dev/guide/authorization
13. Inertia.js — Error handling (dev modal; production error-page rendering for 403/404/500). **High.** https://inertiajs.com/error-handling
14. pundit-community/pundit-matchers — `permit_only_actions` allow-list testing discipline. **High.** https://github.com/pundit-community/pundit-matchers

### Engineering write-ups / secondary

15. Saeloun — Rails Authorization Patterns (Pundit/CanCanCan/Action Policy; default-deny via verify callback; 403 writes / 404 cross-tenant reads; test the "another-account" path). **Medium-high.** https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/
16. daily.dev — Pundit vs CanCanCan vs Action Policy (trade-offs; Pundit = minimal/explicit). **Low-medium** — the URL resolves but only the headline is retrievable via fetch; body content could not be confirmed, so this is **not load-bearing** for any claim (corroborated elsewhere by Saeloun and the palkan discussion). https://daily.dev/posts/pundit-vs-cancancan-vs-action-policy-which-rails-auth-gem-wins--dyuguhmfn
17. Matt Brictson — Rails exception handling (`rescue_responses["Pundit::NotAuthorizedError"] = :forbidden`; content negotiation). **Medium-high.** https://mattbrictson.com/blog/handling-rails-exceptions
18. oneuptime — Pundit authorization in Rails (`rescue_from` + `respond_to` for HTML vs JSON 403). **Medium.** https://oneuptime.com/blog/post/2025-07-02-rails-pundit-authorization/view
19. thoughtbot — JS developer's guide to Rails authorization with Pundit (verify_authorized usage). **Medium.** https://thoughtbot.com/blog/a-javascript-developer-s-guide-to-rails-authorization-with-pundit
20. ShakaCode — Mastering Authorization in Rails with Pundit. **Medium.** https://www.shakacode.com/blog/mastering-authorization-in-rails-with-pundit/
21. Thunderbolt Labs — Testing Pundit policies with RSpec (subject = policy instance; context per user type). **Medium.** https://www.thunderboltlabs.com/blog/2013/03/27/testing-pundit-policies-with-rspec/
22. Indusface — Broken Access Control / client-side controls bypassable; enforce server-side. **Medium-high.** https://www.indusface.com/learning/broken-access-control/
23. Smart Interface Design Patterns — Hidden vs Disabled (hide permission-gated controls). **Medium.** https://smart-interface-design-patterns.com/articles/hidden-vs-disabled/
24. UX Psychology — Hidden vs disabled states. **Medium.** https://uxpsychology.substack.com/p/hidden-vs-disabled-states
25. dev.to (Akarshan) — Soft vs hard delete; trash + grace period. **Medium.** https://dev.to/akarshan/the-delete-button-dilemma-when-to-soft-delete-vs-hard-delete-3a0i
26. koder.ai — Soft vs hard delete trade-offs. **Medium.** https://koder.ai/blog/soft-deletes-vs-hard-deletes
27. Microsoft Entra Learn — Recover from deletions (grace-period recovery). **Medium-high.** https://learn.microsoft.com/en-us/entra/architecture/recover-from-deletions
28. Medium (Suraj Singh Bisht) — soft/hard delete best practices (use `deleted_at` timestamp). **Low-medium.** https://surajsinghbisht054.medium.com/understanding-soft-delete-and-hard-delete-in-software-development-best-practices-and-importance-539a935d71b5
29. Graph AI — Four-eyes principle / dual control (DevOps). **Medium.** https://www.graphapp.ai/engineering-glossary/devops/four-eyes-principle
30. Flagsmith — Four-eyes principle for flag/config changes. **Medium.** https://www.flagsmith.com/blog/what-is-the-four-eyes-principle
31. Wikipedia — Two-person rule / four-eyes principle. **Medium.** https://en.wikipedia.org/wiki/Four_eyes_principle
32. SysCloud / Google Workspace — admin deletion confirmation; dedicated super-admin accounts; data transfer before delete. **Medium.** https://www.syscloud.com/saas-data-protection-center/google-workspace/delete-a-user-from-google-workspace/
33. AppOmni — User roles & least privilege in SaaS. **Medium.** https://appomni.com/learn/saas-security-fundamentals/user-roles-and-least-privilege-in-saas-apps/
34. NinjaOne — Track admin-initiated deletes via SaaS logs (audit views are privileged). **Medium.** https://www.ninjaone.com/blog/use-saas-logs-to-monitor-initiated-deletions/
35. Elastic — Google Workspace admin role detection (admin actions are high-sensitivity). **Medium.** https://www.elastic.co/guide/en/security/current/google-workspace-admin-role-deletion.html
36. RolifyCommunity/rolify — multiple/resource-scoped roles (when to use rolify). **Medium.** https://github.com/RolifyCommunity/rolify
37. RailsApps — Rails authorization (enum vs rolify guidance). **Medium.** https://railsapps.github.io/rails-authorization.html
38. Codersations — Role-based authorization with Rails enum. **Low-medium.** https://gustavocguimaraes.wordpress.com/2014/12/17/role-based-authorization-with-rails-4-enum/comment-page-1/
39. Frontegg / Cynet / BeyondTrust / Arctic Wolf — privilege escalation techniques & defenses (blanket permissions, horizontal escalation, misconfig). **Medium.** https://frontegg.com/blog/privilege-escalation , https://www.cynet.com/network-attacks/privilege-escalation/ , https://www.beyondtrust.com/blog/entry/privilege-escalation-attack-defense-explained , https://arcticwolf.com/resources/glossary/privilege-escalation/
40. GitHub community discussion #175250 — informal confirmation that delete permission is gated (collaborators can't delete; org policy can disable the delete option for non-owner admins). Informal/community source for the observed hidden-control behavior, not official docs. **Low-medium.** https://github.com/orgs/community/discussions/175250

### Conflicting / nuanced sources

- **403 vs 404 for denial.** General guidance says authorization failures = **403** ([#412](https://github.com/varvet/pundit/issues/412)). Multi-tenant guidance says use **404** for cross-tenant reads to avoid existence leakage ([Saeloun](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/)). Resolution: 403 for "you're in the right tenant but lack the role" (our analytics/sessions/delete cases); 404 for "object belongs to another tenant." Not actually contradictory — different threat models.
- **403 vs 302 redirect.** HTTP-correctness and the AC favor **403** ([Matt Brictson](https://mattbrictson.com/blog/handling-rails-exceptions)); some Rails apps use friendly **302+flash** by convention. Resolution in §6.1: return 403 *and* render a friendly page (best of both).
- **Pundit vs Action Policy.** palkan/Action Policy advocates a fuller framework; most general guidance recommends Pundit for clarity/minimalism. Resolution: stay on Pundit (palad-app's needs don't require Action Policy features).

### Web search queries used

1. SaaS workspace deletion owner-only admin best practice destructive action confirmation
2. Pundit vs action_policy Rails authorization comparison trade-offs 2025
3. least privilege default deny policy authorization best practices privilege escalation pitfalls
4. Pundit testing policy specs request specs role matrix RSpec best practices
5. Rails role modeling rolify enumerize admin-only access super_admin best practice
6. Pundit NotAuthorizedError respond 403 forbidden API vs redirect HTML rescue_from
7. GitHub delete repository owner admin permission required typed confirmation
8. OWASP broken object level authorization BOLA insecure direct object reference API top 10
9. Inertia.js Rails error handling 403 forbidden authorization redirect response
10. soft delete vs hard delete SaaS account project recovery grace period best practice
11. hide vs disable button unauthorized UI security defense in depth backend enforcement
12. Vercel delete project team owner role permission RBAC member viewer
13. Notion workspace deletion permission owner admin member role who can delete workspace
14. "two-person rule" OR "four-eyes principle" destructive action approval software dual control
15. Pundit verify_authorized verify_policy_scoped after_action ensure authorization not forgotten controller
16. OWASP A01 broken access control 2021 most common web vulnerability prevention
17. multi-tenant Rails Pundit policy_scope tenant isolation return 404 not 403 cross-tenant information leakage

### Source-verification note

All factual claims about named products/libraries (GitHub, Vercel, Notion, Pundit, Action Policy, Inertia, OWASP) were verified against live web sources via WebSearch/WebFetch on 2026-07-01; internal palad-app claims were verified against the live repo (policy/controller files cited inline). Where a source could not be deep-fetched (e.g., a redirecting URL), the claim is corroborated by at least one other fetched source and marked Medium confidence.
