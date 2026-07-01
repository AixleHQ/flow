---
research_type: technical
research_topic: "Add view-only (Viewer) read-only role"
date: 2026-07-01
web_research_enabled: true
source_verification: true
stepsCompleted: [1, 2, 3, 4, 5, 6]
---

# Read but Don't Touch: Technical Research — Add view-only (Viewer) read-only role

## Executive Summary

A "Viewer" / read-only role is one of the most universally implemented access tiers in collaboration software, and the industry has converged on a small set of patterns we can copy with confidence. Across GitHub, GitLab, Jira, Notion, Figma, and Linear, read-only is almost always a **scoped membership level** (per-repo / per-project / per-file) rather than a single global account flag, and the read-only restriction is **always enforced on the server** with the UI hiding controls purely as a usability layer.

Key findings:

- **Scope is per-resource, not per-account.** GitHub's `Read`, GitLab's `Guest`/`Reporter`, Jira's `Browse Projects`-only role, Figma's `Can view`, and Notion's `Can view` are all attached to a *membership* in a specific resource, not to the global user. A user can be a Viewer in one project and a full editor in another. (See §2.)
- **Server-side authorization is the only real boundary; UI hiding is defense-in-depth UX.** OWASP ranks Broken Access Control as the #1 web risk — A01 in both the 2021 and 2025 Top 10 — and the prevention guidance is explicit that client-side restrictions (hiding buttons, disabling inputs) "can be easily bypassed." Every product enforces read-only server-side. ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html), [OWASP A01:2021](https://owasp.org/Top10/A01_2021-Broken_Access_Control/), [OWASP A01:2025](https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/)) (See §3.)
- **Avoid role explosion by keeping a small fixed set of roles and computing capabilities from them**, rather than letting tenants accumulate near-duplicate role variants (industry consensus across RBAC vendors). ([WorkOS multi-tenant RBAC](https://workos.com/blog/how-to-design-multi-tenant-rbac-saas)) (See §3.)
- **Inertia + Pundit has a first-class, documented pattern** for passing a `can { ... }` permissions object from the server policy into React props for conditional rendering — exactly the capability-flag mechanism we need. ([Inertia Rails Authorization](https://inertia-rails.dev/guide/authorization)) (See §4.)

Top actionable recommendations for palad-app:

1. **Adopt a per-project membership role, not a global `users.role='viewer'`.** This matches every named precedent and the issue Summary ("scoped to a project"). Re-introduce a `role` column on `project_collaborators` (the codebase already had — and then removed — exactly this column; see §5). Confidence: **High** that per-project is the industry norm; **Medium** on overriding the design doc's company-wide shortcut (it depends on whether product wants cross-project read-only users).
2. **Make Pundit the source of truth with a single shared `project_writable?` predicate** threaded into write/execute actions, and **close the un-Punditized `Api::V1::Projects::*` mutation surface** — the largest real gap, since the web policy edits do nothing for the API endpoints the frontend actually posts to (verified in the codebase, §5).
3. **Keep UI hiding, but treat it strictly as UX.** Ship a project-scoped `can` capability object via Inertia shared props and hide run/mutate controls from it. Never rely on it for security.
4. **Branch onboarding by role**: detect viewer membership and collapse/skip the agent-configuration step rather than building a separate onboarding state machine — this matches mainstream "segment early, skip irrelevant steps" onboarding guidance. (See §6.)

---

## Table of Contents

1. [Problem Framing & Research Methodology](#1-problem-framing--research-methodology)
2. [Industry Precedents](#2-industry-precedents)
3. [Patterns & Pitfalls](#3-patterns--pitfalls)
4. [Concrete Libraries & Approaches](#4-concrete-libraries--approaches)
5. [Recommendations for palad-app](#5-recommendations-for-palad-app)
6. [Open Decisions Informed by Research](#6-open-decisions-informed-by-research)
7. [Sources & Confidence](#7-sources--confidence)

---

## 1. Problem Framing & Research Methodology

### What we are building

Ticket #213 asks for a **Viewer** role scoped to a project: a user who can **read** workflows, boards, assets, and analytics, but **cannot** start runs/sessions or create/edit/delete anything. Mutating controls must be **hidden in the UI** and **enforced server-side**. Viewers must also be able to finish onboarding **without** configuring an agent, because the current onboarding state machine hard-gates `step3 → step4` on `has_configured_agents?`.

Our stack: **Ruby on Rails + Pundit** (policy-based authorization) + **React/Inertia/Mantine** + **Postgres**.

### Why research it

The internal design doc (`ai/research/technical-viewer-readonly-role-2026-07-01.md`) surfaces a genuine modeling tension: the ticket *Summary* describes a **per-project** Viewer ("scoped to a project," "a project Owner or Contributor can add a Viewer to any project"), while the *implementation notes* describe a **company-wide** `users.role = 'viewer'`. These are different data models with different blast radii. We want external evidence on how mature products resolve exactly this (scope, granting, enforcement) before committing.

A second, deeper concern raised by the design doc is **defense-in-depth**: the codebase's per-action Pundit policies guard the *web* controller tree, but the React frontend actually posts mutations to an **un-authorized `Api::V1::Projects::*` tree**. So "make Viewer read-only by editing policies" is necessary but **not sufficient** — we need to validate enforcement strategy against best practice.

### How it was researched

Web-search-first. We ran ~12 WebSearch queries and fetched the most authoritative primary sources (official docs for GitHub, GitLab, Jira/Atlassian, Notion, Figma, Linear; OWASP cheat sheets; Pundit and Inertia-Rails docs; WorkOS engineering articles). We then cross-checked findings against the **actual palad-app codebase** (schema, migrations, models, policies, controllers) so recommendations are concrete and not generic. Every non-obvious claim below carries an inline source URL; uncertainty is marked with a confidence level.

---

## 2. Industry Precedents

Across six widely used products, the read-only role is **scoped to a resource (repo/project/file/page)** and granted **per membership**, and read-only is **enforced server-side**. Below, each is described with its actual mechanism.

### 2.1 GitHub — `Read` repository role (repo-scoped)

GitHub defines five repository roles for organizations: **Read, Triage, Write, Maintain, Admin**. `Read` is "recommended for non-code contributors who want to view or discuss your project." ([Repository roles for an organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization))

Concretely, a `Read` user **can** pull/fork, open issues, comment, submit PR reviews, view releases and Actions runs; and **cannot** push code, create releases, apply labels, approve required reviews, manage access, or manage branch protection/rulesets ([same source](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization)).

Key architectural takeaways for us:
- The role is attached at the **repository (resource) level**, granted per-repo via collaborator/team assignment; organizations additionally set a **base permission** org-wide, but admins always retain access regardless ([same source](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization)).
- A small, fixed, ordered ladder of roles (no per-action toggles in the standard product) — this is the anti-role-explosion choice.
- Note: **personal-account repos cannot grant read-only** to collaborators — read-only is an org-tier feature ([Permission levels for a personal account repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository)). Relevance: read-only tiers tend to live where there is a multi-member container (our "project").

### 2.2 GitLab — `Guest` and `Reporter` (project/group-scoped)

GitLab roles operate at **instance, group, and project** levels, and "a user can have different roles for each group and project," always retaining "the permissions for their highest role" ([Roles and permissions](https://docs.gitlab.com/user/permissions/)). This is explicitly **per-resource** role assignment.

- **Guest**: view and comment on issues/epics; **cannot push code or access the repository**.
- **Reporter**: **view code**, create issues, generate/view reports; **cannot push code or manage protected branches** ([same source](https://docs.gitlab.com/user/permissions/)).

GitLab's handling of granularity is instructive for role explosion: rather than minting many roles, it offers **Custom Roles** that are **additive only** — a custom role is based on a default role and can *add* abilities (e.g., a Guest + `read_code`) but **cannot disable** a permission, and "for most features, having `read_*` and `admin_*` should be enough" ([Custom role development guidelines](https://docs.gitlab.com/development/permissions/custom_roles/), [Custom roles](https://docs.gitlab.com/user/custom_roles/)). GitLab also has a **Minimal Access** role for hierarchy gating ([Roles and permissions](https://docs.gitlab.com/user/permissions/)).

Takeaway: keep a small base ladder; if finer control is ever needed, model it as **additive capabilities on top of a base role**, not as new role names.

### 2.3 Jira — `Browse Projects`-only via permission schemes + project roles (project-scoped)

Jira does not ship a literal "Viewer" role; instead read-only is **composed** from a **permission scheme** plus **project roles**. A read-only user is one whose project role is granted **`Browse Projects`** (which controls visibility of the project and its issues) but **not** the `Create Issues` / `Edit Issues` / transition permissions ([Managing project permissions](https://confluence.atlassian.com/adminjiraserver/managing-project-permissions-938847145.html), [Prevent all project edits with a read-only permission scheme](https://support.atlassian.com/jira/kb/prevent-all-project-edits-with-a-read-only-permission-scheme-in-jira/)).

Atlassian explicitly recommends assigning permissions to **project roles rather than users/groups** "to minimize the number of permission schemes" — i.e., a deliberate anti-explosion stance ([Managing project permissions](https://confluence.atlassian.com/adminjiraserver/managing-project-permissions-938847145.html)). Atlassian even publishes a how-to for a dedicated read-only project role (`readonly-users-role` added only to `Browse Projects`) ([Create a read-only user in Jira Cloud](https://support.atlassian.com/jira/kb/create-a-read-only-user-in-jira-cloud/)).

Takeaway: read-only = "read permission granted, write permissions withheld," scoped through a per-project role. This is the **capability-driven** model rather than a hard-coded role flag.

### 2.4 Notion — `Can view` permission level + Guest membership (page/teamspace-scoped, inherited)

Notion's per-page access levels are (six, verbatim from the current docs) **Full access / Can edit / Can edit content / Can create / Can comment / Can view** — where **Can edit content** and **Can create** are only available on **database pages** (and `Can create` is Business/Enterprise-only) ([Sharing & permissions](https://www.notion.com/help/sharing-and-permissions)). `Can view` is the read-only level: people with it "can read the content on the page, but they won't be able to comment, edit, or share" ([same source](https://www.notion.com/help/sharing-and-permissions)). Critically, Notion uses an **inheritance-with-override** model: workspace baseline roles (Owner, Member, Guest) cascade down through **teamspaces**, and individual pages can tighten or loosen access ([WorkOS: multi-tenant permissions](https://workos.com/blog/multi-tenant-permissions-slack-notion-linear)). **Guests** can only access specific pages shared with them ([Manage members & guests](https://www.notion.com/help/add-members-admins-guests-and-groups)).

Takeaway: read-only is a **per-resource permission level** with hierarchical inheritance — the higher container's setting is a default, overridable lower down. We can mirror a (simpler) version: project membership role is the unit, no deep hierarchy needed.

### 2.5 Figma — `Can view` (multi-level: team/project/file, inherited)

Figma assigns access at **team, project, and file** levels, and **`Can view`** is the read-only level. Crucially, **viewing inherits downward**: "By default, each resource inherits permission levels from their parent. This means that a file will inherit the permissions set on the project level, and a project will inherit permissions set on the team level" (with project- and file-level changes overriding the inherited setting). `Can view` at the project level means the user **"cannot create new files"** ([File and project permissions](https://help.figma.com/hc/en-us/articles/35361119554711-File-and-project-permissions)). Figma additionally couples editing to **both a seat and a permission** — "For a user to be able to edit a file, they need both the appropriate seat and permissions" — a billing/seat dimension orthogonal to the role ([same source](https://help.figma.com/hc/en-us/articles/35361119554711-File-and-project-permissions)).

Takeaway: again, **resource-scoped, inherited** read-only. The "edit requires seat + permission" detail is a reminder that capability can be gated by more than one attribute — useful if palad-app ever wants viewers to be non-billable.

### 2.6 Linear — lean global roles (Admin/Member/Guest) + team-scoped access

Linear is the interesting outlier and the closest to our "global role" temptation. It keeps **workspace roles intentionally minimal** (Admin, Member, Guest) and pushes access control to **team membership** and **team owner** roles that exist only within a team's context; **private teams** act as structural access boundaries ([Members and roles](https://linear.app/docs/members-roles), [WorkOS: multi-tenant permissions](https://workos.com/blog/multi-tenant-permissions-slack-notion-linear)). **Guests** (Business/Enterprise only) get **restricted access to specified teams** and cannot discover other teams ([Guest accounts changelog](https://linear.app/changelog/2022-07-14-guest-accounts), [Members and roles](https://linear.app/docs/members-roles)).

Important nuance verified in the docs: Linear's **Guest is not a pure read-only role** — within joined teams, guests can create/edit/comment on issues; the restriction is **scope** (which teams they see), not **mutation** ([Members and roles](https://linear.app/docs/members-roles)). So Linear achieves "limited blast radius" via *scoping*, while GitHub/GitLab/Jira/Figma/Notion achieve "read-only" via a *capability/permission level*. Our Viewer needs **both**: scoped to a project **and** read-only within it.

Takeaway from WorkOS's synthesis of all three (Slack/Notion/Linear): the convergent lesson is "**avoid role explosion by pushing customization to tenant-specific scopes rather than maintaining sprawling global role lists**," with "sensible defaults + opt-in complexity" ([WorkOS: multi-tenant permissions](https://workos.com/blog/multi-tenant-permissions-slack-notion-linear)).

### 2.7 Precedent summary table

| Product | Read-only name | Scope | Granted via | Read-only is… |
|---|---|---|---|---|
| GitHub | `Read` | Repo (+ org base perm) | Per-repo collaborator/team role | Fixed role on ladder |
| GitLab | `Guest` / `Reporter` | Project & group | Per-project/group member role | Fixed roles + additive custom roles |
| Jira | (role w/ `Browse Projects` only) | Project | Project role in permission scheme | Composed capability set |
| Notion | `Can view` | Page/teamspace (inherited) | Per-page/teamspace permission level | Permission level |
| Figma | `Can view` | Org/team/project/file (inherited) | Per-resource permission (+ seat) | Permission level |
| Linear | `Guest` (scope-limited, not pure RO) | Team | Per-team membership | Scope limit, not mutation block |

**Cross-product conclusion (Confidence: High):** read-only is a **per-resource membership capability**, granted at the resource (our project) level, enforced server-side. A purely global account flag is the rare exception (and even Linear, the leanest, scopes by team).

---

## 3. Patterns & Pitfalls

### 3.1 Pattern: Server-side authorization is the source of truth (non-negotiable)

OWASP ranks **Broken Access Control as A01** — the single most critical web application risk — in both the 2021 and the 2025 Top 10 ([OWASP Top 10 A01:2021](https://owasp.org/Top10/A01_2021-Broken_Access_Control/); [OWASP Top 10 A01:2025](https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/), which notes it is "Maintaining its position at #1 in the Top Ten, [with] 100% of the applications tested … found to have some form of broken access control"). The Authorization Cheat Sheet's load-bearing principles, in its own terms ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)):

- **Enforce Least Privileges** — "assigning users only the minimum privileges necessary to complete their job" (for a Viewer: read).
- **Deny by Default** — "the application should be configured to deny access by default."
- **Validate Permissions on Every Request** — "Permission should be validated correctly on every request" — including read requests for the specific object.
- **Server-Side Enforcement** — "Access control checks must be performed server-side, at the gateway, or using serverless function[s]."
- The cheat sheet also warns directly against parameter tampering: "a user should not be able to access a resource they do not have permissions [for] simply because they are able to guess and manipulate that object's identifier in a query param or elsewhere" ([same source](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)).

**Our own derived recommendation (not an OWASP quote):** treat read access itself as a permission requiring authorization on every request, and explicitly test that read-only users cannot modify or delete through parameter manipulation or direct API calls (§3.7, §5.2).

### 3.2 Anti-pattern: UI-only enforcement ("hidden buttons are not authorization")

Hiding or disabling buttons is **not** access control. Attackers (or any curious user) can inspect the client, discover hidden actions, and replay requests directly to the API. Security guidance is blunt on this point: one write-up's prevention rule is "Never rely on client-side checks (e.g., hiding a button in UI)" ([Broken Access Control — OWASP A01](https://rafter.so/blog/broken-access-control)); another states "Client-side restrictions such as hiding buttons or disabling inputs can be easily bypassed. Access control decisions must always be enforced on the server, where users can't manipulate logic" ([Indusface — What Is Broken Access Control](https://www.indusface.com/learning/broken-access-control/); see also [The Browser Is Not a Security Boundary](https://dev.to/trustboundarylab/the-browser-is-not-a-security-boundary-1flj)).

**Direct relevance to palad-app:** the design doc verified that the React app posts mutations (board task CRUD + `trigger_workflow`, asset upload/delete, workflow/step/trigger edits, terminal session create) to the `Api::V1::Projects::*` tree, which currently runs **only** `authenticate_user!` and **no** Pundit `authorize`. So if we only hid buttons + edited the *web* policies, a Viewer could still mutate by hitting the API directly — the textbook A01 mistake. (Verified against the codebase in §5.)

### 3.3 Pattern: verb-based deny-mutation guard vs full per-action policies

Two enforcement styles, both legitimate; OWASP's "defense in depth" favors having a coarse guard *and* fine policies:

- **Verb-based / coarse deny-mutation guard** — a single check (e.g., reject all non-idempotent HTTP verbs, or all actions not on a read allow-list, for read-only users) applied broadly via a `before_action`. Pros: one place, hard to forget, great as a backstop; especially valuable for the un-authorized API tree. Cons: blunt — "mutation" isn't always 1:1 with HTTP verb (a `POST /search` is a read; a `GET /export` may be a write/side-effect), so it can both over- and under-block if used alone.
- **Per-action policy classes** — Pundit's idiom: each action (`create?`, `update?`, `destroy?`, `publish?`, …) is explicitly allowed/denied in a policy class. Pros: auditable per action, matches palad-app's existing convention, testable. Cons: must remember to author/guard every action; easy to leave a new endpoint unguarded (exactly what happened to the API tree).

**Recommended (defense in depth):** use **both** — per-action Pundit policies as the precise source of truth, *plus* a coarse "deny mutations for read-only" backstop on controller base classes (and especially on the API tree) so a forgotten policy fails closed. This is the layered approach OWASP prescribes ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)).

### 3.4 Pattern: Pundit "deny by default" + `verify_authorized`

Deny-by-default in Pundit is something **you** implement, not a built-in default the README documents: in real Pundit, calling a predicate that isn't defined raises `NotImplementedError`/`NoMethodError` rather than silently returning `false`. The conventional deny-by-default comes from the **generated `ApplicationPolicy` template** (`rails g pundit:install`), whose default action methods return `false`, and which your policies inherit from — the README itself says "you'll probably want to inherit from the application policy created by the generator" ([Pundit README](https://github.com/varvet/pundit)). So we get deny-by-default by inheriting from that generated base and only overriding to *grant*. (Confidence: **Medium-High** — the behavior is well established but lives in the generator template, not in README prose.)

Critically, Pundit ships `verify_authorized` (and `verify_policy_scoped` for index) as **`after_action` hooks** that *raise if `authorize`/`policy_scope` was never called* — the mechanism that catches the "forgot to guard this action" class of bug ([Pundit README](https://github.com/varvet/pundit); [codemancers: Pundit best practices](https://www.codemancers.com/blog/2018-07-29-leveraging-pundit)). The current README recommends a single combined `after_action` that branches on the action name:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  after_action :verify_pundit_authorization

  def verify_pundit_authorization
    if action_name == "index"
      verify_policy_scoped
    else
      verify_authorized
    end
  end
end
```

(The older idiom — `after_action :verify_authorized, except: :index` plus `after_action :verify_policy_scoped, only: :index` — is still functional but is no longer what the README shows.) The README also notes you can `skip_authorization`/`skip_policy_scope` for deliberate exceptions ([Pundit README](https://github.com/varvet/pundit)). **Pitfall relevant to us:** if the API tree never calls `authorize`, `verify_authorized` is *also* not enabled there, so nothing flags the gap — adding this verification to the API base controller would itself surface every unguarded action.

### 3.5 Pattern: capability flags server→client for conditional rendering

The mainstream approach: the server computes the authorization result and sends a **`can { ... }` permissions object** to the client, which conditionally renders/hides controls. "When a user logs in, the server responds with a set of permissions… read and updated in the client-side state," and "this mechanism is not intended to prevent unauthorized requests to the server — it is more of a UX improvement" ([DEV: conditional render by permissions](https://dev.to/worldlinetech/how-to-conditionally-render-react-ui-based-on-user-permissions-2amg); [Permit.io: React RBAC](https://www.permit.io/blog/implementing-react-rbac-authorization)). This is exactly the Inertia-Rails idiom in §4.

### 3.6 Anti-pattern: role explosion via context-encoded roles

Role explosion is a well-documented RBAC failure mode: you ship sensible defaults (Admin / Editor / Viewer), then accumulate near-duplicate variants no one can tell apart. WorkOS describes the pattern concretely — "Tenant creates 8 variants of 'Editor.' Six months later no one remembers what any of them do" — and attributes it largely to a lack of visibility into how roles differ ([WorkOS: multi-tenant RBAC](https://workos.com/blog/how-to-design-multi-tenant-rbac-saas)). (A related driver, cited across other RBAC vendors as paraphrased industry consensus, is encoding user-specific context — region, department, project, level — into role names rather than computing it.) The fix is the same either way: **keep a small set of base roles and evaluate capabilities/attributes dynamically**, rather than minting a role per (project × permission) combination. GitLab's additive custom roles and Jira's permission-scheme composition are production examples of this discipline (§2.2, §2.3).

**Direct relevance:** do *not* create `project_viewer`, `project_contributor`, `project_owner_admin`, etc. as separate global roles. Model **one small `role` enum on the project membership** (e.g., `viewer`/`contributor`/`manager`) and compute `writable?`/`executable?` from it.

### 3.7 Edge-case traps to test

- **Mutation hiding behind GET/non-obvious verbs** — `export`, `download`, `duplicate`, `trigger_workflow` may have side effects; classify each by *intent*, not HTTP verb (§3.3).
- **"Last admin" / ownership invariants** — ensure a Viewer can never be the project owner and that demoting to Viewer doesn't strip the last manager (the codebase already has a `user_is_not_owner` validation on `project_collaborator` and a `cannot_demote_last_admin` on `User`).
- **Inherited/elevated access** — a company admin or project owner who is *also* a Viewer elsewhere must keep their higher role where it applies (GitLab's "highest role wins" rule, §2.2).
- **Parameter tampering on reads** — OWASP: verify viewers cannot reach another project's data by changing IDs ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)).
- **Stale client capability flags** — if a user is demoted to Viewer mid-session, the cached `can` object is stale; server enforcement still protects, but invalidate/refresh on navigation.

---

## 4. Concrete Libraries & Approaches (Rails + Pundit + React/Inertia)

### 4.1 Pundit (already in palad-app) — read/write split + scopes

Pundit is "minimal authorization through OO design and pure Ruby classes," policies live in `app/policies`, query methods map to actions (`update?`, `create?`), and `policy_scope` filters collections for index actions ([Pundit README](https://github.com/varvet/pundit)). For a read-only role the idiomatic move is to **compose a predicate**:

```ruby
def update?  = project_writable?   # write/execute actions
def destroy? = project_writable?
def index?   = project_accessible? # read actions stay on the read gate

private
def project_writable?
  project_accessible? && !current_user_read_only_in?(project)
end
```

This mirrors palad-app's existing one-liner policy style (e.g., `RepositoriesPolicy#create? = project_accessible? && current_user.admin?`, verified in the repo). Inherit policies from the generator's `ApplicationPolicy` (whose default action methods return `false`) so unimplemented actions deny by default, and add the `verify_pundit_authorization` after_action hook (§3.4) as the backstop.

### 4.2 Inertia-Rails authorization — the capability-flag mechanism we want

Inertia-Rails documents the pattern for our "hide controls" requirement: compute policy results server-side and pass them as a **`can` prop**. The documented example actually uses **Action Policy's `allowed_to?`** ([Inertia Rails Authorization](https://inertia-rails.dev/guide/authorization)):

```ruby
# As documented on inertia-rails.dev (Action Policy):
can: { create_user: allowed_to?(:create, User) }
```

Since palad-app uses **Pundit**, the equivalent — written by us, not copied from the docs — replaces `allowed_to?(:action, record)` with `policy(record).action?`:

```ruby
# Our Pundit adaptation:
render inertia: "Projects/Show", props: {
  can: {
    start_run:   policy(project).start_run?,
    create_item: policy(project).create?
  },
  # ...
}
```

The React side consumes `can.start_run` to render/hide the run button. The Inertia-Rails guide and the Inertia.js core docs are explicit that **authorization belongs on the server** — "When using Inertia, authorization is best handled server-side in your application's authorization policies" ([Inertia.js — Authorization](https://inertiajs.com/docs/v2/security/authorization)); the `can` prop is for display only and **must never be the access boundary** (our characterization; neither page states a literal "UX-only" sentence). palad-app already shares a `permissions` object via `inertia_share` (`{ is_admin, can_manage_members, can_manage_projects }`, verified in `Web::Company::ApplicationController`); we extend this with a **project-scoped** `can` block.

### 4.3 Pundit vs Action Policy (do we need to switch?)

We do **not** need to switch. Both gems support per-action policies and scopes. Per the cited comparison, Action Policy "keeps the policy-object shape, adds useful Rails integration, and supports features such as authorization reasons, aliases, scoping, and caching for expensive checks" ([Saeloun: Rails authorization patterns](https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/)); it additionally ships first-class RSpec/Minitest matchers per its own documentation ([Action Policy](https://actionpolicy.evilmartians.io/)). Pundit is smaller and explicit/review-friendly. For #213, staying on Pundit is the lower-risk choice (Confidence: High). Action Policy's `allowed_to?` is what the Inertia-Rails docs example happens to use, but Pundit's `policy(record).action?` is equivalent for prop-building.

### 4.4 Data modeling library/idiom — `has_many :through` membership with a role column

For a per-project role, the Rails-idiomatic structure is a **join model** (`ProjectCollaborator`) used via `has_many :through`, with a `role` column on the join — "use `has_many :through` when the relationship is a thing in its own right… most join tables eventually sprout additional columns" ([Rails Association Basics](https://guides.rubyonrails.org/association_basics.html); [DEV: HABTM vs has_many:through](https://dev.to/hasan-dev/habtm-hasmany-through-sti-and-polymorphic-associations-in-rails-5dlp)). palad-app already has this join model — it just lacks the role column today (and had one briefly; see §5). Enumerize (already used for `users.role`) is the natural way to constrain the membership role values.

### 4.5 React conditional rendering helpers

The community patterns are a `useCan()`/`usePermissions()` hook or a small `<Can permission="start_run">` wrapper component reading the shared `can` object ([Permit.io: React RBAC](https://www.permit.io/blog/implementing-react-rbac-authorization); [DEV: conditional render by permissions](https://dev.to/worldlinetech/how-to-conditionally-render-react-ui-based-on-user-permissions-2amg)). With Inertia, the `can` prop is available via `usePage().props`. Keep it dead simple — a typed `can` object in shared props plus inline `can.start_run && <Button .../>`.

---

## 5. Recommendations for palad-app

These are tied to the verified current state of the codebase (schema, models, policies, controllers as of this research).

### 5.1 Verified current state (load-bearing facts)

- `users.role` is `enumerize :role, in: %i[employee admin super_admin]` (`app/models/user.rb:20`); schema has a non-null `role` string with an index (`db/schema.rb`).
- `project_collaborators` **currently has NO role column** (only `project_id`, `user_id`, timestamps) — confirmed in `db/schema.rb`.
- **However**, the repo's migration history shows a `role` column *was* added then removed: `db/migrate/20260120201225_create_project_collaborators.rb` created `t.string :role, null: false, default: "contributor"` with a comment "Role within project: **viewer, contributor (default), manager**" and an index, and `db/migrate/20260120201758_remove_role_from_project_collaborators.rb` removed it. **The per-project-role design was started and reverted.** (The `15-7-cleanup-remove-custom-viewer` artifact is unrelated — it concerns the agent-session watcher UI, not the role.)
- Project read gate today: `Project#accessible_by?(user)` = owner OR collaborator row OR same-company admin; `Project#admin?(user)` = is owner. Every project policy delegates to `project_accessible?`, except a few owner/admin-gated write actions (e.g., `BoardsPolicy` create/update/destroy, `RepositoriesPolicy`/`IntegrationsPolicy` writes). There is **no read/write tier** today.
- **The critical enforcement gap:** the React app posts mutations to `Api::V1::Projects::*`, whose base controllers run `authenticate_user!` only and call **no** Pundit `authorize` (verified: no `authorize`/`dynamic_authorize!` anywhere under `app/controllers/api/`). Web policy edits do nothing for these endpoints.
- Frontend permission plumbing already exists: `inertia_share { permissions: { is_admin:, can_manage_members:, can_manage_projects: } }` in `Web::Company::ApplicationController` — but **no project-scoped capability flag** is shared.

### 5.2 What to pick

1. **Model: per-project membership role (re-introduce `project_collaborators.role`).** Restore the very column the repo already designed: `role` enum `viewer | contributor | manager` (default `contributor`), with an index, plus the matching `enumerize` on `ProjectCollaborator`. This matches every industry precedent (§2) and the ticket Summary's "scoped to a project." Owners remain via `projects.owner_id`; same-company admins keep their elevated access. Confidence: **High** (industry-aligned, and the codebase already shaped this).
   - *If product insists on a cross-project, person-is-always-read-only flag*, a company-wide `users.role='viewer'` is simpler but blunter (read-only everywhere) and diverges from precedent — treat as the fallback, not the default. See §6.1.

2. **Enforcement: Pundit as source of truth + close the API gap + coarse backstop (defense in depth).**
   - Add a shared predicate `project_writable?` = `project_accessible? && !viewer_in?(project)` and flip **write/execute** actions in the project policies to it; keep **read** actions on `project_accessible?`. This is the smallest diff in the established per-action style.
   - **Add Pundit authorization to the `Api::V1::Projects::*` tree** (the real mutation surface) — wire `dynamic_authorize!` (the codebase's existing dynamic dispatch) + `verify_authorized` into the API base controller so unguarded actions fail closed. Prioritize: board task CRUD + `trigger_workflow`, asset create/destroy, workflow/step/trigger edits, terminal session create (`Api::V1::TerminalSessionsController#create`, the agent-session launch path).
   - Add a **coarse read-only backstop** `before_action` on the project base controllers that denies non-read actions for viewers, so a future un-guarded action still fails closed. Confidence: **High** that both layers are warranted (OWASP defense-in-depth).

3. **UI: ship a project-scoped `can` object via Inertia shared props; hide run/mutate controls from it.** Extend the existing shared `permissions` with project-scoped flags (`can_run`, `can_mutate`, …) computed from the policy, and gate Mantine buttons/menus on them. Treat strictly as UX (§3.2, §4.2). Confidence: **High**.

4. **Onboarding: branch by role to skip agent setup.** Detect "this user is only a viewer" and collapse the agent-selection + authenticate steps. Prefer relaxing the existing state-machine guard for viewers over building a parallel machine (§6.4). Confidence: **Medium** (depends on whether a viewer can exist with zero non-viewer memberships at onboarding time — see §6.4 caveat).

5. **Tests.** There are no Pundit policy unit tests today (Minitest project). Add: policy specs that a viewer is denied every write/execute action; **integration tests hitting the API endpoints directly** to prove a viewer cannot mutate via API (the parameter-tampering / direct-request case OWASP calls out); and an onboarding test that a viewer completes without agent credentials.

---

## 6. Open Decisions Informed by Research

### 6.1 Global `users.role='viewer'` vs per-project membership role

**Decision: per-project membership role (`project_collaborators.role`), with global flag as fallback only.**

Every named precedent that implements a true read-only tier does so **per-resource** (GitHub repo `Read`, GitLab project `Guest`/`Reporter`, Jira project role, Notion/Figma `Can view` per page/file), and even the leanest (Linear) scopes by team rather than globally ([GitHub](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization), [GitLab](https://docs.gitlab.com/user/permissions/), [Jira](https://support.atlassian.com/jira/kb/create-a-read-only-user-in-jira-cloud/), [WorkOS](https://workos.com/blog/multi-tenant-permissions-slack-notion-linear)). A global `users.role='viewer'` forces a person to be read-only **everywhere**, which the precedents avoid and which the ticket Summary contradicts ("add a Viewer to *any* project"). The codebase already designed (and reverted) the `project_collaborators.role` column — re-introducing it is low-risk and idiomatic (`has_many :through` with a role column, [Rails guides](https://guides.rubyonrails.org/association_basics.html)). To avoid role explosion, keep the membership enum tiny (`viewer/contributor/manager`) and compute capabilities from it ([WorkOS RBAC](https://workos.com/blog/how-to-design-multi-tenant-rbac-saas)).

**Confidence: High** that per-project is the correct industry-aligned model. **Medium** on the operational call to override the internal design doc's company-wide shortcut — that hinges on a product question (do we ever want a person who is read-only across all their projects?). If yes-and-only-ever, the global flag is acceptable as a simpler v1; if read-only-ness varies by project (the Summary's framing), per-project is required.

### 6.2 Server-side enforcement: verb-based deny-mutation guard vs full per-action Pundit policies

**Decision: both — per-action Pundit policies as the source of truth, plus a coarse deny-mutation backstop, and critically extend authorization to the un-guarded API tree.**

OWASP prescribes **defense in depth** and **deny by default** ([OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)). Per-action policies match palad-app's convention and are auditable, but they are easy to forget (the API tree proves it). A coarse `before_action` that blocks non-read actions for viewers is a cheap fail-closed backstop. A pure verb-based guard alone is risky because "mutation" ≠ HTTP verb (e.g., `trigger_workflow`, `export`, `duplicate` have side effects) (§3.3). Adding Pundit `verify_authorized` to the API base controller will *surface* every currently-unguarded action ([Pundit README](https://github.com/varvet/pundit)).

**Confidence: High.**

### 6.3 Is UI hiding acceptable given server-side enforcement?

**Decision: yes — UI hiding is expected and good UX, but only as a layer on top of server enforcement; never as the boundary.**

This is the universal industry/OWASP position: client-side restrictions "can be easily bypassed," and "access control decisions must always be enforced on the server, where users can't manipulate logic" ([Indusface — What Is Broken Access Control](https://www.indusface.com/learning/broken-access-control/)); the prevention rule is to "never rely on client-side checks (e.g., hiding a button in UI)" ([Rafter: Broken Access Control](https://rafter.so/blog/broken-access-control)). Inertia-Rails documents the `can`-prop pattern and states that "authorization is best handled server-side in your application's authorization policies" ([Inertia Rails Authorization](https://inertia-rails.dev/guide/authorization), [Inertia.js core docs](https://inertiajs.com/docs/v2/security/authorization)) — the `can` prop is for display only, never the boundary (our characterization). So: ship the `can` capability object to hide run/mutate controls (better UX than a viewer clicking a button and getting a 403), **and** enforce identically on the server. Do not skip either layer.

**Confidence: High.**

### 6.4 Onboarding bypass approach for viewers

**Decision: branch the existing onboarding flow by role and collapse/skip the agent-configuration step — do not build a separate transition/state machine.**

Mainstream onboarding guidance is to **segment users early by role and route them into a tailored path that skips irrelevant steps** ([Userflow: onboarding strategies](https://help.userflow.com/docs/onboarding-strategies); [Userpilot: onboarding UX](https://userpilot.com/blog/onboarding-ux-examples/)), and conditional gateways that skip steps based on a user attribute are a standard workflow pattern ([Knack: onboarding workflow automation](https://www.knack.com/blog/onboarding-workflow-automation/)). Concretely: relax the `step3 → step4` guard (`has_configured_agents?`) and `can_complete_onboarding?` for viewers so the agent-credential requirement is waived, and hide the "Select Agents"/"Authenticate" steps in the React `Stepper` for viewers. This reuses the existing `UserStateMachine` rather than forking it, keeping one code path.

**Caveat / open sub-question (Confidence: Medium):** onboarding today is **per-user, company-scoped**, while the recommended Viewer is **per-project**. At onboarding time a brand-new invitee may not yet have any project membership, so "is this user a viewer?" may be undefined globally. Options: (a) carry a viewer signal on the invitation (invite-as-viewer), so onboarding knows to skip agent setup; or (b) make agent setup **always optional/skippable** and let users add credentials later when they first need to run something — which is also better general UX ("always provide a clear way to skip," [DesignerUp study of 200 onboarding flows](https://designerup.co/blog/i-studied-the-ux-ui-of-over-200-onboarding-flows-heres-everything-i-learned/)). Recommend (b) as the simplest robust path if it fits product; otherwise (a). This is the one decision where the per-project model adds friction and product input is most valuable.

---

## 7. Sources & Confidence

### Web search queries used
1. GitHub repository roles read-only viewer permission levels read access
2. GitLab project member roles Guest Reporter read-only permissions
3. Jira project roles viewer read-only permission scheme
4. Notion guest member viewer read-only full access permission levels page sharing
5. Figma viewer role can view edit permissions file project organization
6. Linear member guest role permissions read-only workspace
7. Pundit Rails authorization read-only policy verb-based deny mutation defense in depth
8. RBAC per-project membership role vs global user role data modeling trade-offs role explosion
9. capability flags server to client conditional rendering permissions React hide buttons policy frontend
10. UI-only authorization security risk client-side hiding buttons enforce server side OWASP
11. role-based onboarding flow skip steps conditional onboarding viewer read-only user bypass setup
12. Pundit policy_scope authorize controller best practices deny by default verify_authorized
13. Rails membership join table role column polymorphic project_collaborators has_many through pattern multi-tenant
14. Pundit permitted_attributes serialize policy to JSON frontend Inertia capabilities permissions object
15. GitLab custom roles read-only minimal access role explosion granular permissions design
16. Inertia.js share props permissions policy authorization React conditional rendering Rails Pundit
17. action_policy gem vs pundit policy caching scopes Rails authorization comparison

### Numbered source list

1. **GitHub — Repository roles for an organization** — High — https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization
2. **GitHub — Permission levels for a personal account repository** — High — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository
3. **GitLab — Roles and permissions** — High — https://docs.gitlab.com/user/permissions/
4. **GitLab — Custom roles** — High — https://docs.gitlab.com/user/custom_roles/
5. **GitLab — Custom role development guidelines** — High — https://docs.gitlab.com/development/permissions/custom_roles/
6. **Atlassian — Managing project permissions (Jira)** — High — https://confluence.atlassian.com/adminjiraserver/managing-project-permissions-938847145.html
7. **Atlassian — Prevent all project edits with a read-only permission scheme** — High — https://support.atlassian.com/jira/kb/prevent-all-project-edits-with-a-read-only-permission-scheme-in-jira/
8. **Atlassian — Create a read-only user in Jira Cloud** — High — https://support.atlassian.com/jira/kb/create-a-read-only-user-in-jira-cloud/ (canonical target; the legacy `confluence.atlassian.com/jirakb/...779160729.html` URL 301-redirects here)
9. **Notion — Sharing & permissions** — High — https://www.notion.com/help/sharing-and-permissions
10. **Notion — Manage members & guests** — High — https://www.notion.com/help/add-members-admins-guests-and-groups
11. **Figma — File and project permissions** — High — https://help.figma.com/hc/en-us/articles/35361119554711-File-and-project-permissions
12. **Linear — Members and roles** — High — https://linear.app/docs/members-roles
13. **Linear — Guest accounts (changelog)** — Medium (changelog, may lag current product) — https://linear.app/changelog/2022-07-14-guest-accounts
14. **WorkOS — Multi-tenant permissions (Slack/Notion/Linear)** — High — https://workos.com/blog/multi-tenant-permissions-slack-notion-linear
15. **WorkOS — How to design multi-tenant RBAC for SaaS (role explosion)** — High — https://workos.com/blog/how-to-design-multi-tenant-rbac-saas
16. **OWASP — Authorization Cheat Sheet** — High — https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html
17. **OWASP — Top 10 A01:2021 Broken Access Control** — High — https://owasp.org/Top10/A01_2021-Broken_Access_Control/
17b. **OWASP — Top 10 A01:2025 Broken Access Control** (confirms BAC remains #1 in 2025) — High — https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/
18. **Rafter — Broken Access Control (OWASP A01)** — Medium (vendor blog; cited for "Never rely on client-side checks (e.g., hiding a button in UI)") — https://rafter.so/blog/broken-access-control
19. **Indusface — What Is Broken Access Control** — Medium (vendor blog; cited verbatim for "Client-side restrictions … can be easily bypassed. Access control decisions must always be enforced on the server …") — https://www.indusface.com/learning/broken-access-control/
20. **DEV — The Browser Is Not a Security Boundary** — Medium — https://dev.to/trustboundarylab/the-browser-is-not-a-security-boundary-1flj
21. **Pundit — README (varvet/pundit)** — High — https://github.com/varvet/pundit
22. **codemancers — Using Pundit: recipes & best practices** — Medium — https://www.codemancers.com/blog/2018-07-29-leveraging-pundit
23. **Saeloun — Rails Authorization Patterns: Pundit, CanCanCan, Action Policy** — Medium — https://blog.saeloun.com/2026/04/28/rails-authorization-patterns-complete-guide/
24. **Action Policy — official site** — High — https://actionpolicy.evilmartians.io/
25. **Inertia Rails — Authorization guide** — High — https://inertia-rails.dev/guide/authorization
26. **Inertia.js — Authorization (core docs)** — High — https://inertiajs.com/docs/v2/security/authorization
27. **Permit.io — Implementing RBAC authorization in React** — Medium — https://www.permit.io/blog/implementing-react-rbac-authorization
28. **DEV — How to conditionally render React UI based on user permissions** — Medium — https://dev.to/worldlinetech/how-to-conditionally-render-react-ui-based-on-user-permissions-2amg
29. **Rails Guides — Active Record Associations (has_many :through)** — High — https://guides.rubyonrails.org/association_basics.html
30. **DEV — HABTM vs has_many:through vs STI vs polymorphic** — Medium — https://dev.to/hasan-dev/habtm-hasmany-through-sti-and-polymorphic-associations-in-rails-5dlp
31. **Userflow — User onboarding strategies** — Medium — https://help.userflow.com/docs/onboarding-strategies
32. **Userpilot — Onboarding UX examples** — Medium — https://userpilot.com/blog/onboarding-ux-examples/
33. **Knack — Onboarding workflow automation (conditional gateways)** — Medium — https://www.knack.com/blog/onboarding-workflow-automation/
34. **DesignerUp — Lessons from 200 onboarding flows** — Medium — https://designerup.co/blog/i-studied-the-ux-ui-of-over-200-onboarding-flows-heres-everything-i-learned/

### Conflicting-source notes
- **Linear's "Guest" is not a pure read-only role.** The Linear docs and WorkOS describe Guest as *scope-limited* (restricted to specific teams) while still allowing create/edit within those teams ([12](https://linear.app/docs/members-roles), [14](https://workos.com/blog/multi-tenant-permissions-slack-notion-linear)). Some secondary write-ups loosely call it "read-only," which is inaccurate. We treat Linear as a *scoping* precedent, not a read-only-tier precedent.
- **Pundit "deny by default" lives in the generator, not the README.** The Pundit README does not show a base `ApplicationPolicy` whose action methods return `false`, nor state deny-by-default for unimplemented methods (an undefined predicate actually raises). Deny-by-default comes from the **generated** `ApplicationPolicy` template you inherit from; the README only points you at it ([21](https://github.com/varvet/pundit)). We recommend inheriting from that generated base (default-deny) + explicit per-action grants + a coarse backstop.
- **Inertia capability-flag example uses Action Policy's `allowed_to?`**, whereas palad-app uses Pundit; the equivalent is `policy(record).action?`. Not a true conflict, just a syntax difference noted to avoid copy-paste confusion ([25](https://inertia-rails.dev/guide/authorization)).

### Overall confidence
- Industry precedents (per-resource, server-enforced read-only): **High** — primary vendor docs.
- Enforcement strategy (defense-in-depth, deny-by-default, close API gap): **High** — OWASP primary + verified codebase gap.
- Capability-flag UI pattern via Inertia: **High** — official Inertia-Rails docs.
- Per-project vs global decision *for palad-app specifically*: **Medium** — sound by precedent, but the final call depends on a product question (cross-project read-only?) and on reconciling onboarding scope (§6.4).
