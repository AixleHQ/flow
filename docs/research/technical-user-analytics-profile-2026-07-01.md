# Technical Design — #303 User Analytics Profile

> Status: Proposed · Date: 2026-07-01 · Author: design exploration
>
> Scope note: research + design only. No code was run; all claims are grounded in
> files cited as `path:line`.
>
> **Scope revision (2026-07-01):** the product scope expanded. This doc now covers a
> GitHub-style contribution/activity heatmap (shown in **both** the user profile and
> the project view), **cross-person** viewing (any authenticated company member may
> view another member's activity — not admin-gated), the "sessions launched" metric
> as the activity unit, an all-participants project view with a per-participant
> filter, and a sessions list on the profile. Previously-agreed decisions (on-the-fly
> SQL for v1, three slice-specific services, reuse of the existing Recharts panels,
> composite `(user_id, created_at)` indexes) are preserved.

## 1. Problem & Goal

Users have no cross-project view of their own — or a teammate's — platform usage.
The profile page (`app/controllers/web/profile_controller.rb:8`,
`app/frontend/pages/Profile/Show.tsx:659-793`) only exposes account settings:
personal info, default agent runtime, default models, and agent-credential
management (`Show.tsx:709-789`; `maw={600}` centered box at `:704`; **no tabs
today**). There is no "how much has this person used the platform this month,
where, and at what cost" view, and no way to see another team member's activity.

Rich analytics already exist, but only scoped to a **project** or to the **company**:

- Project analytics — `Web::Company::Projects::AnalyticsController`
  (`app/controllers/web/company/projects/analytics_controller.rb:4-81`) backed by
  `ProjectAnalyticsService`, `AgentActivityService`, `SessionCostTokenUsageService`,
  `SessionSourceBreakdownService`, `SessionDurationDistributionService`,
  `WorkflowCostAnalyticsService`. It already supports a `scope=user` ("My Activity")
  segmented toggle (`app/frontend/pages/Projects/Analytics/AnalyticsPage.tsx:839-847`)
  but that only filters a **single** project to the **current** user (no way to view
  *another* participant, and no all-participants daily overview).
- Company analytics — `Web::Company::AnalyticsController`
  (`app/controllers/web/company/analytics_controller.rb:4-59`) backed by
  `CompanyAnalyticsService` etc. It already produces a **per-project breakdown**
  (`CompanyAnalyticsService#build_project_breakdowns`, `app/services/company_analytics_service.rb:75-99`).

Both analytics stacks already compute a **daily** per-agent activity series via
`date_trunc('day', ...)` grouping (`AgentActivityService#activity_over_time`,
`app/services/agent_activity_service.rb:52-67`; company variant
`app/services/company_agent_activity_service.rb:48-63`) — but nothing renders it as a
**contribution heatmap**; the FE only draws a stacked area chart from it
(`buildActivityChartData`, `app/frontend/pages/Company/Analytics/AnalyticsPage.tsx:130-138`).
A frontend grep for `heatmap`/`calendar`/`contribution`/`getDay` finds **no existing
component** — the calendar grid is net-new.

**Goals (expanded scope):**

1. Add a personal **Usage** view to the profile that aggregates usage scoped to a
   **target user** across all their projects, filterable by time period, with a
   per-project breakdown — reusing the existing chart UI and mirroring the existing
   service/controller patterns.
2. Add a **GitHub-style contribution heatmap** (calendar grid of daily activity)
   rendered in **both** the profile Usage view **and** the project analytics view,
   fed by a reusable daily-bucket series and a single reusable React component.
3. Make the profile Usage view **cross-person**: any authenticated company member can
   view another member's activity (`GET /profile/usage?user_id=…`), authorized by
   "requester and target are in the same company" (**not** admin-gated). The
   self-view (`user_id` omitted → `current_user`) keeps working.
4. In the **project** view, show **all participants'** activity by default, with the
   ability to filter to a **single participant**.
5. Add a **sessions list** to the profile Usage view — the target user's
   `terminal_sessions`, reusing the existing `Company/Sessions/Index` patterns
   (`app/controllers/web/company/sessions_controller.rb:4-21`,
   `app/frontend/pages/Company/Sessions/Index.tsx`), scoped to the target user.

The activity metric is **launched sessions** (`terminal_sessions`). Workflow runs
ultimately manifest as sessions — a `WorkflowRun` has many `StepRun`s
(`app/models/workflow_run.rb:13`), and each executed step gets a
`session_type: "workflow_step"` `TerminalSession` created by
`SessionService.create_for_workflow_step` (`app/services/session_service.rb:44-82`,
type set at `:60`, linked back at `step_run.update!(terminal_session:)` `:73`). So
**sessions are the unit**; workflow runs are still reported as a separate headline
count (`workflows_run`) for context, but the heatmap and per-day activity count
sessions.

> Invariant that shapes the whole design: `TerminalSession belongs_to :project,
> optional: true` (`app/models/terminal_session.rb:13`). Project-less sessions are
> **not** limited to `auth_setup`/`tool_setup` — `SessionService.create_and_start`
> defaults `project: nil` (`app/services/session_service.rb:5`) and explicitly
> handles project-less sessions at `:141-147` (`if session.project` → company-scoped
> fallback), so an `agent_session` (or `workflow_step`) can carry a null `project_id`
> in production. The `:agent_session` factory trait also leaves `project { nil }`
> (`test/factories/terminal_sessions.rb:43-45`, inheriting the top-level
> `project { nil }` at `:6`). The user service therefore reads
> `user.terminal_sessions` directly (no company table to anchor a `joins(:project)`),
> so it must decide explicitly how project-less in-scope rows are counted — and must
> keep the per-project breakdown reconciling with the summary total via
> `left_joins(:project)` + a **"(No project)"** bucket (§4, §5).

All raw data already carries `user_id`:

- `terminal_sessions.user_id` — `null: false` (`db/schema.rb:662`), indexed
  (`db/schema.rb:670-672`: `user_id`, `(user_id, session_type)`, `(user_id, state)` —
  **none** leads with `(user_id, created_at)`).
- `workflow_runs.user_id` — `null: false` (`db/schema.rb:896`), indexed on `user_id`
  alone (`db/schema.rb:902`).
- `usage_statistics` belongs to a session via `terminal_session_id`
  (`db/schema.rb:807`, unique index `db/schema.rb:811`); user is reached through
  the session join. `terminal_sessions` also carries denormalized `cost_cents` /
  `total_tokens` columns (`db/schema.rb:638`, `:660`), kept in sync by
  `TerminalSession#sync_usage` (`app/models/terminal_session.rb:193-208`).

So **no new ingestion and no schema change for correctness** is required (see
§4 Data migration for an optional index).

## 2. Current State (how it works today)

### 2.1 The closest mirror: `CompanyAnalyticsService`

`app/services/company_analytics_service.rb` is the single best template because it
already emits a per-project breakdown and supports a `scope=user` filter:

- Period mapping `PERIOD_DAYS` (`:5-9`) — `7d/30d/90d/1y` → days; default 30.
- `Result` struct includes `project_breakdowns` (`:13-17`).
- `scope_sessions` joins sessions to projects by company and optionally filters by
  user (`:55-58`):
  ```ruby
  base = TerminalSession.joins(:project).where(projects: { company_id: company.id })
  scope == "user" ? base.where(user:) : base
  ```
- `usage_stats_for` sums cost + tokens with the canonical token expression — sum of
  the four breakdown columns, falling back to the legacy `tokens` column when the
  breakdown is all-zero (`:60-68`):
  ```ruby
  COALESCE(NULLIF(SUM(input_tokens + output_tokens + cache_write_tokens + cache_read_tokens), 0), SUM(tokens), 0)
  ```
- `base_workflow_runs` counts runs joined to company projects, optionally by user
  (`:70-73`).
- `build_project_breakdowns` groups sessions by `projects.id, projects.name`, LEFT
  JOINs `usage_statistics`, orders by total cost desc, and maps to a
  `ProjectBreakdown` struct (`:75-99`).

### 2.2 Other per-metric services (project + company variants)

The project-scoped variants all accept `(project:, user:, scope:, period:, tags:, task_type:)`,
include `TaskFilterable` (`app/services/concerns/task_filterable.rb`), branch on
`scope == "user"` via `project.terminal_sessions.where(user:)`:

- `AgentActivityService` (`app/services/agent_activity_service.rb`) — agent-type
  breakdown (`sessions_by_agent`, struct `AgentBreakdown` with `agent_type, sessions,
  cost_cents, tokens`) + daily activity time series (`activity_over_time`, struct
  `ActivityPoint` with `date, agent_type, sessions`). Note: it reads cost/tokens
  off the **denormalized** `terminal_sessions.cost_cents`/`total_tokens` columns
  (`:36-39`), whereas the company variant joins `usage_statistics`
  (`app/services/company_agent_activity_service.rb:28-34`). Both are valid — the
  denormalized columns are kept in sync by `TerminalSession#sync_usage`
  (`app/models/terminal_session.rb:193-208`).
- `SessionCostTokenUsageService` (`app/services/session_cost_token_usage_service.rb`)
  and `CompanySessionCostTokenUsageService`
  (`app/services/company_session_cost_token_usage_service.rb`) — daily/weekly/monthly
  cost+token time series. Bucket granularity comes from `DATE_TRUNC_KEY`
  (`7d/30d→day, 90d→week, 1y→month`, `company_session_cost_token_usage_service.rb:11-16`).
- `SessionSourceBreakdownService` (`app/services/session_source_breakdown_service.rb`)
  — counts by `session_type` with human labels (`SOURCE_LABEL`, `:13-18`).
- `WorkflowCostAnalyticsService` (`app/services/workflow_cost_analytics_service.rb`)
  — per-workflow cost/token/duration with `input_tokens`/`output_tokens` columns
  surfaced separately (`:96-100`); tested by
  `test/services/workflow_cost_analytics_service_test.rb`.

Several analytics-adjacent service tests already exist and are closer mirrors for
parts of the new service than the controller-level company test:
`test/services/session_cost_token_usage_service_test.rb` (time-series buckets),
`test/services/session_source_breakdown_service_test.rb` (group-by-type),
`test/services/session_duration_distribution_service_test.rb`, and
`test/services/workflow_cost_analytics_service_test.rb` (legacy-token fallback,
period windowing). Note: there is **no** `company_analytics_service_test.rb`, so the
"closest mirror" `CompanyAnalyticsService` is itself untested — the new
`UserAnalyticsService` should ship its own unit test (§7) rather than lean on a
non-existent company-service test.

### 2.2b The daily-bucket series that already feeds the heatmap

The exact SQL for the contribution heatmap's daily series **already exists** in the
agent-activity services and needs only to be reused (not invented):

```ruby
# AgentActivityService#activity_over_time  (agent_activity_service.rb:52-67)
sessions.where.not(agent_type: nil)
  .group("date_trunc('day', terminal_sessions.created_at)", :agent_type)
  .order("1 ASC")
  .pluck("date_trunc('day', terminal_sessions.created_at)", :agent_type, "COUNT(*)")
  .map { |date, agent_type, count| ActivityPoint.new(date: date.to_date.iso8601, agent_type:, sessions: count) }
```

`ActivityPoint` is `Struct.new(:date, :agent_type, :sessions)`
(`agent_activity_service.rb:14`; company variant `:12`). This is a per-`(day, agent)`
tuple, ISO-8601 date, session **count** — precisely the shape a contribution grid
needs, except the heatmap wants **one total per day** (summed across agents), so the
new heatmap series drops the `:agent_type` group (§4 `ActivityHeatmapService`). Note
`activity_over_time` filters `agent_type IS NOT NULL`, so a heatmap built on the exact
same query would drop `workflow_step` rows that have a null `agent_type`; the new
service must **not** re-apply that filter (the heatmap counts all launched sessions).

### 2.2c The Company/Sessions index (to reuse for the profile sessions list)

`Web::Company::SessionsController#index` (`app/controllers/web/company/sessions_controller.rb:4-21`):

- Starts from `company_sessions_scope` (defined on the company base controller,
  `app/controllers/web/company/application_controller.rb:48-52`):
  ```ruby
  TerminalSession.left_joins(:project)
    .where("terminal_sessions.user_id IN (?) OR projects.company_id = ?",
           current_company.users.select(:id), current_company.id)
  ```
- `.with_cached_resource_counts` (adds `session_logs_count` /
  `pending_review_assets_count` subselects), then eager-loads
  `:user, :project, :tools, :skills, :mcp_servers, :input_assets, :repositories`
  (`:6-8`), **excludes** `session_type: "auth_setup"` (`:9`), applies
  `.ransack(q_params).result` (`:10`), orders `created_at: :desc` (`:12`).
- Ransackable attributes: `%w[agent_type project_id session_type state created_at user_id]`
  (`app/models/terminal_session.rb:53`) — crucially includes `user_id`, so scoping to
  a target user is expressible as a ransack predicate `q[user_id_eq]`.
- Paginated via `inertia_scroll(scope)` (Pagy, `PaginationConcern`; default per_page
  20, max 100), serialized per row through `TerminalSessionResource.new(s).to_h`.
- Props: `sessions` (scroll), `filters` (q_params), `per_page`.
- Frontend `app/frontend/pages/Company/Sessions/Index.tsx`: a filters bar (agent /
  status / per-page, `:187-216`), an `InfiniteScroll` table with columns ID / Agent /
  Type / Status / User / Project / Tokens / Cost / Models / Duration / Started
  (`:234-246`), a `Session` row interface (`:11-33`), and an accumulating
  `sessionMap` kept in sync with Cable updates (`:112-141`). `SessionRow` at `:263-362`.

The profile sessions list reuses `TerminalSessionResource` and the `Session`
row/`SessionRow` rendering, but scopes to the **target user** via
`target_user.terminal_sessions` (see §4 controller). It intentionally does **not**
reuse `company_sessions_scope` (that scope is company-wide; we want a single user).

### 2.3 Controllers and the deferred-prop convention

Both analytics controllers render an Inertia page and wrap each metric in
`InertiaRails.defer(group: "analytics")` so the page shell paints immediately and
panels stream in (`analytics_controller.rb:12-58`,
`projects/analytics_controller.rb:16-80`). Props are **camelCased inline** in the
controller (e.g. `totalSessions:`, `projectBreakdowns:`) — these analytics payloads
are **not** Alba resources and therefore **not** Typelizer-generated (see §4 Frontend).

Filter params come from the query string with defaults:
`scope = params.fetch(:scope, "company"|"project")`,
`period = params.fetch(:period, "30d")`.

### 2.4 Profile controller and page

- `Web::ProfileController < Web::ApplicationController` (`app/controllers/web/profile_controller.rb:3`).
  It does **not** include Pundit and does not call `authorize`; it gates on
  `before_action :require_auth` (`:6`, `:47-49`) and operates entirely on
  `current_user`. `Web::ApplicationController` provides `current_user`
  (via `AuthConcern`) and the always-shared `current_user`/`projects` props
  (`app/controllers/web/application_controller.rb` `inertia_share`). It does **not**
  define `current_company` — that lives on `Web::Company::ApplicationController:36-38`.
- `#show` renders `"Profile/Show"` with `profile`, `language_options`,
  `agent_models`, `cable_stream` (`:8-15`).
- Frontend `app/frontend/pages/Profile/Show.tsx` is a single-column settings page
  (`<Box maw={600}>`, `:704`) composed of cards: Personal Information, Default
  Agent Runtime, Default Models, Agent Runtimes. There are **no tabs today**.
- Nav entry: `app/frontend/shared/ui/AppSidebar.tsx:424-426` — `<Menu.Item ... href="/profile">`
  `My Profile`.
- Route: `resource :profile, only: %i[show update]` (`config/routes.rb:186-189`)
  with member routes `update_default_model`, `destroy_credential`.

> **Cross-person wrinkle (new scope):** `ProfileController` is a *singular*
> `resource :profile` scoped to `current_user`. For the cross-person Usage view we
> need to view an **arbitrary same-company user**, so the target is a `user_id`
> **query param**, not a nested route resource. Because the profile is singular and
> the target is optional (defaults to self), a `user_id` param on the new `usage`
> member action is the minimal shape — the URL stays `/profile/usage[?user_id=…]`. We
> do **not** move usage under a plural `users` namespace for v1 (that is a larger
> refactor and the profile is the natural home for "someone's usage").

### 2.4b Company membership & same-company authorization (for cross-person)

- `User belongs_to :company, optional: true` (`app/models/user.rb:24`); `user.company_id`
  is the FK. `Web::Company::ApplicationController#current_company` is
  `current_user.company` (`app/controllers/web/company/application_controller.rb:36-38`).
  `ProfileController` inherits from `Web::ApplicationController`, which does **not**
  define `current_company` — so the usage action derives the company from
  `current_user.company` directly.
- The **same-company** check is `current_user.company_id == target_user.company_id`
  (both non-nil). The existing precedent for company-scoped lookup is
  `ProjectsPolicy#current_project = current_user.company.projects.find_by(id: …)`
  (`app/policies/web/company/projects_policy.rb:24-27`) — "look the record up *within*
  the current user's company," which returns nil (→ not-authorized) for out-of-company
  ids. The usage action applies the same "scope-before-find" idea:
  `current_user.company.users.find(params[:user_id])` (raising `RecordNotFound` →
  404 for a foreign user), defaulting to `current_user` when `user_id` is absent.
- The existing analytics/sessions policies are permissive no-ops
  (`Web::Company::AnalyticsPolicy#index? = true`,
  `app/policies/web/company/analytics_policy.rb`;
  `Web::Company::SessionsPolicy#index?/show?/new? = true`,
  `app/policies/web/company/sessions_policy.rb`). `ProfileController` uses **no
  Pundit** — it gates only on `require_auth`. So cross-person authorization here is a
  same-company scope guard in the controller, not a Pundit `authorize` call (§4, §5,
  OQ-6). This matches how the rest of `ProfileController` already works.

### 2.5 Data model facts that shape the design

- `TerminalSession belongs_to :project, optional: true` (`app/models/terminal_session.rb:13`).
  `user.terminal_sessions` therefore includes **project-less** sessions. Critically,
  this is **not** limited to `auth_setup`/`tool_setup`: `SessionService.create_and_start`
  defaults `project: nil` (`app/services/session_service.rb:5`) and branches on
  `if session.project` at `:141`, so an `agent_session` can be created project-less in
  production; the `:agent_session` factory trait likewise leaves `project { nil }`
  (`test/factories/terminal_sessions.rb:43-45`, inheriting the top-level
  `project { nil }` at `:6`). Only `:auth_setup` *forces* `project { nil }`
  (`:38-41`), but a null `project_id` is legal for **every** session_type. Session
  types are `auth_setup | agent_session | tool_setup | workflow_step`
  (`app/models/terminal_session.rb:35-38`). The project/company analytics services
  anchor on a company table via `joins(:project).where(projects: { company_id: ... })`
  (`company_analytics_service.rb:56`), so project-less rows are naturally excluded
  there. A user service reading `user.terminal_sessions` directly has no such anchor
  and must decide explicitly how to treat project-less rows so the per-project
  breakdown still reconciles with the summary total (see §4, §5).
- Agent types: `claude_code | cursor_cli | codex | gemini_cli`
  (`app/models/terminal_session.rb:40-43`).
- `User#projects` returns owned ∪ collaborated projects
  (`app/models/user.rb:81-84`); `Project.for_user` widens to whole company for
  admins (`app/models/project.rb:52-58`). Personal usage must use **session
  ownership** (`terminal_sessions.user_id`), not project membership, so the numbers
  are "what this person did", independent of project access changes.
- **Project participants** (for the project view's participant filter) =
  owner + collaborators. `Project.member_users` returns exactly that set, owner
  first (`app/models/project.rb:95-98`):
  ```ruby
  User.where(id: [owner_id] + project_collaborators.pluck(:user_id))
      .order(Arel.sql("CASE WHEN id = #{owner_id} THEN 0 ELSE 1 END"))
  ```
  (`owner` at `project.rb:13`; `collaborators` through `project_collaborators` at
  `:14-15`.) The participant `Select` in the project view is populated from
  `project.member_users`; the "all participants" default simply omits the
  `user_id` filter.
- **Session types** are `auth_setup | agent_session | tool_setup | workflow_step`
  (`app/models/terminal_session.rb:35-38`). The metric "launched sessions" counts
  `agent_session` + `workflow_step` and excludes `auth_setup`/`tool_setup`
  (bookkeeping sessions) — mirroring the Company/Sessions index, which also excludes
  `auth_setup` (`sessions_controller.rb:9`). See §5 for the exact treatment and OQ-1.

## 3. Proposed Design

Add a self-contained personal analytics stack that mirrors the company stack but is
keyed off a **target user** instead of `company`, served under the profile context;
plus a **reusable contribution-heatmap** component + a small daily-bucket series
service used by **both** the profile and the project views.

**Approach (chosen):**

1. **Three slice-specific aggregate services keyed off a target user**, mirroring the
   company trio (`CompanyAnalyticsService` + `CompanyAgentActivityService` +
   `CompanySessionCostTokenUsageService`):
   - `UserAnalyticsService` → summary totals + per-project breakdown (with the
     "(No project)" bucket).
   - `UserAgentActivityService` → per-agent breakdown.
   - `UserSessionCostTokenUsageService` → cost/token time series.

   Each takes `user:` (the **target** user) + `period:` (+ optional `project_id:`
   drill-down). Splitting mirrors the company stack and avoids one service being
   re-run 3x across deferred blocks (OQ-4). The user view drops tags/task_type,
   the duration histogram, and the per-workflow table (not required by the ACs).
2. **A reusable daily-bucket heatmap series** — `ActivityHeatmapService` — that
   returns one `{date, count}` per day for the period (sessions launched), usable in
   two scopes: *user* (`user.terminal_sessions`) and *project*
   (`project.terminal_sessions`, all participants or one). This reuses the exact
   `date_trunc('day', …)` SQL already in `AgentActivityService#activity_over_time`
   (`agent_activity_service.rb:52-67`) but **without** the `agent_type` grouping and
   **without** the `agent_type IS NOT NULL` filter (the heatmap counts every launched
   session, including `workflow_step` rows with null `agent_type`).
3. **A reusable `ContributionHeatmap` React component** (`shared/ui/`) that renders a
   GitHub-style calendar grid from a `{date, count}[]` series. Used on **both**
   `Profile/Usage.tsx` and `Projects/Analytics/AnalyticsPage.tsx`.
4. **New action `usage` on the profile controller** (`Web::ProfileController#usage`)
   rendering a dedicated Inertia page `Profile/Usage`, with an optional `user_id`
   param (the **target** user; defaults to `current_user`), a `period` param, an
   optional `project_id`, and `InertiaRails.defer(group: "usage")` props. The action
   resolves + authorizes the target via a same-company scope guard (§4), then feeds
   all four services with the resolved target. It also adds a **sessions** deferred
   prop (the target user's `terminal_sessions`, reusing `TerminalSessionResource`).
5. **New route** `get :usage` as a member route on the existing `resource :profile`.
6. **Convert the profile page to a tabbed layout**: `Profile/Show` keeps the settings
   UI under an "Account" tab; a new "Usage" tab links to `/profile/usage`. `Profile/Usage.tsx`
   reuses the chart panels from `Company/Analytics/AnalyticsPage.tsx` (summary stat
   grid, per-project breakdown table, agent pie, daily cost/token area charts), adds
   the `ContributionHeatmap`, and adds a sessions table ported from
   `Company/Sessions/Index.tsx`. When viewing another user, it shows a header banner
   ("Viewing {name}'s usage").
7. **Project view enhancements** (`Projects/Analytics/AnalyticsController` +
   `AnalyticsPage.tsx`): (a) drop in the `ContributionHeatmap` fed by a new
   `activity_heatmap` deferred prop showing **all participants by default**; (b) add a
   **participant `Select`** (populated from `project.member_users`) that sets a
   `participant_id` param, filtering every panel to one participant. The existing
   `scope=user` ("My Activity") toggle is preserved; `participant_id` is orthogonal
   (it targets a *chosen* participant rather than the current user).

**Rationale**

- **Cross-person is a controller-side same-company scope guard, not Pundit.** The
  target is resolved with `current_user.company.users.find(params[:user_id])` (or
  `current_user` when absent), so a request can only ever reach a user in the
  requester's own company (foreign id → `RecordNotFound` → 404). This is *not*
  admin-gated by design (any member may view any same-company member), matching the
  permissive analytics/sessions policies (`analytics_policy.rb`, `sessions_policy.rb`
  are `= true`) and `ProfileController`'s no-Pundit convention. See §5 / OQ-6.
- **Sessions are the activity unit.** Launched sessions (`agent_session` +
  `workflow_step`) are counted; workflow runs are reported as a context headline but
  not double-counted, because each executed workflow step already *is* a
  `workflow_step` session (`session_service.rb:44-73`).
- Reusing the company page's React panels/inline interfaces + one shared heatmap
  component keeps the FE consistent and avoids inventing new chart styling.

**Rejected alternatives**

- *Reuse `CompanyAnalyticsService` with `scope=user`.* Rejected: it scopes by
  `projects.company_id` (`company_analytics_service.rb:56`) and a `super_admin` has no
  company (`user.rb:24`/`:42`, `company_id` may be nil); it still filters to a single
  company's projects and would misroute project-less sessions inconsistently. A
  personal view is session-ownership-based, not company-membership-based.
- *Admin-gate cross-person viewing.* Rejected per the confirmed requirement: any
  authenticated same-company member may view another member's activity (the ethics
  guardrail is met by self-visibility + same-company transparency, not by role
  gating — see research §3.4). The only guard is same-company.
- *A new `users/:id/usage` plural route.* Rejected for v1 as a larger routing
  refactor; a `user_id` query param on `profile#usage` is the minimal shape (§2.4).
- *Add a persistent `user_usage_aggregates` rollup table.* Rejected for v1:
  on-the-fly aggregation already performs acceptably at project/company scope. Noted
  as a future option in §8.
- *Server-compute everything in one prop.* Rejected: breaks the per-panel `Deferred`
  streaming UX and the matching test helpers (`assert_inertia_deferred_props`).
- *A charting-library heatmap dependency.* Rejected: a contribution grid is a simple
  CSS-grid of `<rect>`/`<div>` cells colored by intensity bucket — no new dependency;
  Recharts (already present, `^3.8.0`) is not needed for the grid itself.

## 4. Detailed Changes

### Backend

Three slice-specific services mirror the company trio, each keyed off a **target
user** (the caller resolves + authorizes that user; §"Controller" below). For
readability the reference implementation below is written as a single
`UserAnalyticsService` carrying all metrics, but the shipped shape is **three
services** — `UserAnalyticsService` (summary + project breakdown),
`UserAgentActivityService` (agent breakdown; mirror `CompanyAgentActivityService`),
`UserSessionCostTokenUsageService` (time series; mirror
`CompanySessionCostTokenUsageService`) — so no deferred block recomputes another's
aggregates (OQ-4). The `build_agent_breakdowns` / `build_time_series` methods shown
here are the bodies of the latter two services.

#### New: `app/services/user_analytics_service.rb` (+ two slice services)

Mirror `CompanyAnalyticsService` but key off the target `user`; drop the `:project`
join from the base scope (sessions belong to the user directly) and add
`agent_breakdown` + `time_series` to the result. Decision: **restrict to billable
session types** (`agent_session`, `workflow_step`) so auth/tool-setup noise does not
inflate the "sessions launched" count (see §5, OQ-1) — this is the metric definition
for the whole feature.

> **Reconciliation invariant (must hold).** In-scope billable sessions can still be
> **project-less** (`agent_session`/`workflow_step` with `project_id = nil`; see §2.5).
> An INNER `joins(:project)` in `build_project_breakdowns` (as the company service
> does at `company_analytics_service.rb:77`) would silently **drop** those rows, so
> `sum(projectBreakdowns.sessions) < total_sessions` and the AC "per-project
> contribution to the totals" would not reconcile — failing the §8 staging check.
> The user service therefore uses `left_joins(:project)` and emits an unconditional
> **"(No project)"** bucket (`project_id = nil`) so the breakdown always sums back to
> the summary totals (sessions, cost, and tokens). Counting project-less billable
> sessions is also the correct user-facing behavior: those are real sessions the user
> launched. This differs from `CompanyAnalyticsService`, which can use an inner join
> only because its company anchor (`joins(:project).where(projects: ...)`) already
> requires a project.

```ruby
# frozen_string_literal: true

class UserAnalyticsService
  PERIOD_DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  DATE_TRUNC_KEY = { "7d" => "day", "30d" => "day", "90d" => "week", "1y" => "month" }.freeze
  # Session types that represent real, billable usage (exclude auth_setup / tool_setup).
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  ProjectBreakdown = Struct.new(:project_id, :project_name, :sessions, :cost_cents, :tokens, keyword_init: true)
  AgentBreakdown   = Struct.new(:agent_type, :sessions, :cost_cents, :tokens, keyword_init: true)
  TimeSeriesPoint  = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)

  Result = Struct.new(
    :total_sessions, :total_cost_cents, :total_tokens,
    :avg_cost_cents_per_session, :workflows_run,
    :project_breakdowns, :agent_breakdowns, :time_series,
    keyword_init: true
  )

  def initialize(user:, period:, project_id: nil)
    @user       = user
    @period     = period.to_s
    @since      = PERIOD_DAYS.fetch(@period, 30).days.ago
    @project_id = project_id.presence # optional drill-down to a single project
  end

  def call
    sessions = base_sessions
    stats    = usage_stats_for(sessions)
    total_sessions = sessions.count

    Result.new(
      total_sessions:,
      total_cost_cents: stats[:cost_cents],
      total_tokens: stats[:tokens],
      avg_cost_cents_per_session: total_sessions.positive? ? (stats[:cost_cents].to_f / total_sessions).round : 0,
      workflows_run: base_workflow_runs.count,
      project_breakdowns: build_project_breakdowns(sessions),
      agent_breakdowns: build_agent_breakdowns(sessions),
      time_series: build_time_series(sessions)
    )
  end

  private

  attr_reader :user, :period, :since, :project_id

  def base_sessions
    scope = user.terminal_sessions
                .where(created_at: since.., session_type: USAGE_SESSION_TYPES)
    project_id ? scope.where(project_id:) : scope
  end

  # Reuse the canonical cost/token expression from CompanyAnalyticsService:60-68.
  def usage_stats_for(sessions)
    row = UsageStatistic
      .where(terminal_session_id: sessions.select(:id))
      .pick(
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(input_tokens + output_tokens + cache_write_tokens + cache_read_tokens), 0), SUM(tokens), 0)")
      )
    { cost_cents: row[0].to_i, tokens: row[1].to_i }
  end

  def base_workflow_runs
    # Uses the new WorkflowRun.for_user_in_period scope (positional args, mirroring
    # for_project_in_period/for_user_in_project at workflow_run.rb:23-24) so the
    # scope is not dead code. If the scope is not added, inline:
    #   WorkflowRun.where(user:, created_at: since..)
    runs = WorkflowRun.for_user_in_period(user, since)
    project_id ? runs.where(project_id:) : runs
  end

  # Same shape as CompanyAnalyticsService#build_project_breakdowns:75-99 but groups
  # the user's own sessions. CRITICAL difference from the company service: it uses
  # LEFT JOIN (left_joins(:project)) instead of the company's INNER joins(:project)
  # so project-less billable sessions (agent_session/workflow_step with project_id
  # NULL — legal per terminal_session.rb:13, session_service.rb:5/141) are NOT
  # dropped. They group into a single "(No project)" bucket (projects.id IS NULL),
  # which guarantees sum(project_breakdowns.{sessions,cost_cents,tokens}) equals the
  # summary totals (reconciliation invariant; see §5 and the dedicated test in §7).
  def build_project_breakdowns(sessions)
    sessions
      .left_joins(:project)
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group("projects.id", "projects.name")
      .order(Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0) DESC"))
      .pluck("projects.id", "projects.name",
             Arel.sql("COUNT(terminal_sessions.id)"),
             Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
             Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)"))
      .map { |id, name, c, cost, tok| ProjectBreakdown.new(project_id: id, project_name: name || "(No project)", sessions: c.to_i, cost_cents: cost.to_i, tokens: tok.to_i) }
  end

  # Mirrors CompanyAgentActivityService:26-44 (joins usage_statistics for cost/tokens).
  def build_agent_breakdowns(sessions)
    sessions
      .where.not(agent_type: nil)
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group(:agent_type)
      .pluck(:agent_type,
             Arel.sql("COUNT(terminal_sessions.id)"),
             Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
             Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)"))
      .map { |t, c, cost, tok| AgentBreakdown.new(agent_type: t, sessions: c.to_i, cost_cents: cost.to_i, tokens: tok.to_i) }
      .sort_by { |a| -a.sessions }
  end

  # Mirrors CompanySessionCostTokenUsageService:30-51.
  def build_time_series(sessions)
    trunc = DATE_TRUNC_KEY.fetch(period, "day")
    trunc_sql = Arel.sql("DATE_TRUNC('#{trunc}', terminal_sessions.created_at)")
    sessions
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group(trunc_sql).order(trunc_sql)
      .pluck(trunc_sql,
             Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
             Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)"))
      .map { |d, cost, tok| TimeSeriesPoint.new(date: d.to_date.iso8601, cost_cents: cost.to_i, total_tokens: tok.to_i) }
  end
end
```

Why this exact shape: the cost/token SQL is copied verbatim from
`CompanyAnalyticsService:60-68` and `CompanySessionCostTokenUsageService:42-43`, so
the legacy-`tokens` fallback (relied on by
`workflow_cost_analytics_service_test.rb:128-146`) behaves identically. The
input/output/cache **breakdown** the AC mentions is derivable from `usage_statistics`
the same way `WorkflowCostAnalyticsService:96-97` surfaces `input_tokens`/`output_tokens`;
if PM wants the explicit 3-way split chart we add `input_tokens`/`output_tokens`/
`cache_tokens` columns to `TimeSeriesPoint` (see OQ-3). v1 ships total tokens like the
company page does.

#### New: `app/services/activity_heatmap_service.rb` (reusable — user AND project)

The GitHub-style heatmap needs **one session count per calendar day** over a window
(GitHub shows ~53 weeks; we align the window to the selected `period`, defaulting to
365 days so the grid always looks like a year). This is the `activity_over_time` SQL
minus the agent grouping and minus the `agent_type IS NOT NULL` filter (§2.2b), so it
counts **all** launched sessions including `workflow_step` rows with a null
`agent_type`.

```ruby
# frozen_string_literal: true

class ActivityHeatmapService
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze
  DayCount = Struct.new(:date, :count, keyword_init: true)

  # scope: an ActiveRecord relation of terminal_sessions (already narrowed to a
  #   user, a project, or a project+participant by the caller).
  # days: window length (default 365 → a full contribution-year grid).
  def initialize(scope:, days: 365)
    @scope = scope
    @since = days.to_i.days.ago.beginning_of_day
  end

  def call
    day = Arel.sql("date_trunc('day', terminal_sessions.created_at)")
    @scope
      .where(created_at: @since.., session_type: USAGE_SESSION_TYPES)
      .group(day).order(day)
      .pluck(day, Arel.sql("COUNT(terminal_sessions.id)"))
      .map { |d, c| DayCount.new(date: d.to_date.iso8601, count: c.to_i) }
  end
end
```

Callers build the `scope`:

- **User (profile):** `ActivityHeatmapService.new(scope: target_user.terminal_sessions)`.
- **Project, all participants (default):** `ActivityHeatmapService.new(scope: project.terminal_sessions)`.
- **Project, one participant:** `ActivityHeatmapService.new(scope: project.terminal_sessions.where(user_id: participant_id))`.

Gap-filling (empty days rendered as level-0 cells) is done in the `ContributionHeatmap`
component (it iterates every date in the window and defaults missing days to 0), so the
service returns only non-empty days — the same convention the existing time-series
charts rely on (research §3.2; OQ-7 records the FE-vs-BE choice, resolved to FE here).

#### New: `app/controllers/web/profile_controller.rb#usage` (cross-person)

Add a `usage` action mirroring `analytics_controller.rb:4-59` but driven by a
**resolved, same-company-authorized target user** and the `group: "usage"` defer
group. `user_id` (optional) selects the target; absent → `current_user`. `project_id`
(optional) is the per-project drill-down. The three metric services are wired as
distinct slice services (OQ-4).

```ruby
def usage
  target     = resolve_target_user      # same-company guard; see below
  period     = params.fetch(:period, "30d")
  project_id = params[:project_id].presence

  render inertia: "Profile/Usage", props: {
    period:,
    project_id:,
    viewer_is_self: target == current_user,
    target_user: { id: target.id, name: target.name, email: target.email },
    summary: InertiaRails.defer(group: "usage") {
      r = UserAnalyticsService.new(user: target, period:, project_id:).call
      {
        totalSessions: r.total_sessions, totalCostCents: r.total_cost_cents,
        totalTokens: r.total_tokens, avgCostCentsPerSession: r.avg_cost_cents_per_session,
        workflowsRun: r.workflows_run,
        projectBreakdowns: r.project_breakdowns.map { |p|
          # projectId is nil for the "(No project)" bucket (project-less sessions).
          { projectId: p.project_id, projectName: p.project_name, sessions: p.sessions, costCents: p.cost_cents, tokens: p.tokens }
        }
      }
    },
    agent_activity: InertiaRails.defer(group: "usage") {
      r = UserAgentActivityService.new(user: target, period:, project_id:).call
      { sessionsByAgent: r.sessions_by_agent.map { |a| { agentType: a.agent_type, sessions: a.sessions, costCents: a.cost_cents, tokens: a.tokens } } }
    },
    cost_token: InertiaRails.defer(group: "usage") {
      r = UserSessionCostTokenUsageService.new(user: target, period:, project_id:).call
      { timeSeries: r.time_series.map { |p| { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens } } }
    },
    activity_heatmap: InertiaRails.defer(group: "usage") {
      scope = project_id ? target.terminal_sessions.where(project_id:) : target.terminal_sessions
      { days: ActivityHeatmapService.new(scope:).call.map { |d| { date: d.date, count: d.count } } }
    },
    sessions: InertiaRails.defer(group: "usage") {
      scope = target.terminal_sessions
                    .where.not(session_type: "auth_setup")          # mirror sessions_controller.rb:9
                    .includes(:user, :project).order(created_at: :desc)
      inertia_scroll(scope) { |records| records.map { |s| TerminalSessionResource.new(s).to_h } }
    }
  }
end

private

# Same-company scope guard (NOT admin-gated). Foreign / unknown user_id → 404.
def resolve_target_user
  return current_user if params[:user_id].blank?
  current_user.company.users.find(params[:user_id])   # ActiveRecord::RecordNotFound → 404
end
```

Notes:
- **Authorization = the scope guard**, exactly like `ProjectsPolicy#current_project`
  looks projects up *within* `current_user.company` (`projects_policy.rb:24-27`). Any
  authenticated member may view any same-company member; no role check (requirement).
  A `super_admin` has `company_id = nil`; `current_user.company.users` would raise on a
  nil company — but super_admins never reach `/profile` (they are redirected to the
  admin panel by `redirect_super_admin_to_admin_panel`, `application_controller.rb:48-50`),
  so this path is unreachable for them (§5).
- The `sessions` prop reuses `TerminalSessionResource` and `inertia_scroll`
  (`PaginationConcern`) exactly as `SessionsController#index` (`sessions_controller.rb:14-20`),
  but scoped to `target.terminal_sessions` instead of `company_sessions_scope`. It
  keeps the `auth_setup` exclusion (`:9`). Ransack filters can be layered later; v1
  ships the target user's sessions ordered `created_at: :desc`.
- Each deferred block calls **one** slice service, so no block recomputes another's
  aggregates (the OQ-4 concern, resolved by the three-service split).

> Implementation note (why three services): if a single `UserAnalyticsService.call`
> computed every metric and were invoked once per deferred block, the page would do
> ~3x the aggregate work (each `.call` recomputes summary + agent + time-series). The
> company controller avoids this by wiring three distinct services
> (`CompanyAnalyticsService` + `CompanyAgentActivityService` +
> `CompanySessionCostTokenUsageService`). We mirror that. The single-service reference
> code above is for readability only; ship the split. (OQ-4.)

#### Changed: `app/controllers/web/company/projects/analytics_controller.rb` — heatmap + participant filter

Add two things to `index` (`projects/analytics_controller.rb:4-81`), preserving the
existing `scope`/`period`/`tags`/`task_type` params and the six existing deferred props:

- Read an optional `participant_id = params[:participant_id].presence`. When present,
  narrow every metric to that one participant; when absent, **all participants** (the
  default). The cleanest wiring is to pass `participant_id` into the existing services
  as an extra keyword (they already accept `user:` for the `scope=user` path — a
  `participant_id` filter is `project.terminal_sessions.where(user_id: participant_id)`).
  For v1 the heatmap alone strictly needs it; extending the other panels to honor
  `participant_id` is the "filter by participant" AC and is a small additive change to
  each service's `scope_sessions` (e.g. `AgentActivityService#scope_sessions`
  `agent_activity_service.rb:84-90`).
- Add a new deferred prop `activity_heatmap` (group `"analytics"`):
  ```ruby
  activity_heatmap: InertiaRails.defer(group: "analytics") {
    scope = participant_id ? project.terminal_sessions.where(user_id: participant_id)
                           : project.terminal_sessions
    { days: ActivityHeatmapService.new(scope:).call.map { |d| { date: d.date, count: d.count } } }
  },
  participants: project.member_users.map { |u| { id: u.id, name: u.name, email: u.email } }  # for the Select
  ```
  `participants` is a plain (non-deferred) prop feeding the participant `Select`
  (`project.member_users`, `project.rb:95-98`).

#### Changed: `config/routes.rb:186-189`

Add a member `get :usage`:

```ruby
resource :profile, only: %i[show update], controller: "profile" do
  get :usage, on: :member          # GET /profile/usage  → profile_usage_path
  put :update_default_model, on: :member
  delete :destroy_credential, on: :member
end
```

This regenerates `profileUsagePath()` in `app/frontend/shared/routes.ts`
(JS routes are generated; cf. existing `updateDefaultModelProfilePath` exported at
`shared/routes.ts:856`, body `:855-858`).

#### Policies — cross-person authorization is a same-company scope guard, not Pundit

`ProfileController` has no Pundit (`policy_context`/`authorize` live only on
`Web::Company::ApplicationController:28-30`). Cross-person authorization is enforced by
`resolve_target_user` looking the target up **within** `current_user.company.users`
(above), so an out-of-company or unknown `user_id` yields `RecordNotFound` (404) and a
requester can never see a user outside their own company. This is deliberately **not**
admin-gated (any member may view any same-company member — requirement), consistent
with the permissive `Web::Company::AnalyticsPolicy#index? = true`
(`analytics_policy.rb`) and `SessionsPolicy` (`sessions_policy.rb`), and with
`ProfileController`'s no-Pundit convention. If a reviewer wants an explicit policy for
symmetry, it would be a `ProfilePolicy#usage?` returning
`current_user.company_id.present? && current_user.company_id == record.company_id`
(where `record` is the target user) — functionally identical to the scope guard.
Decision recorded in §5 / OQ-6.

#### Models — no change required

`User has_many :terminal_sessions` (`user.rb:30`) and the implicit
`WorkflowRun.where(user:)` are sufficient. Optional readability helper: a
`WorkflowRun.for_user_in_period` scope analogous to the existing
`for_project_in_period`/`for_user_in_project` (`app/models/workflow_run.rb:23-24`),
which use **positional** args. For parity add
`scope :for_user_in_period, ->(user, since) { where(user: user, created_at: since..) }`
(positional `(user, since)`, matching the neighbors' style). **If added, the service
must actually use it** — `base_workflow_runs` below is updated to call
`WorkflowRun.for_user_in_period(user, since)` rather than inlining the `where`, so the
scope is not dead code. If the team prefers not to add the scope, drop this
recommendation and keep `base_workflow_runs` inlining `WorkflowRun.where(user:, ...)`.

### Frontend

#### Changed: `app/frontend/pages/Profile/Show.tsx`

Wrap the existing settings cards in a Mantine `Tabs` with two tabs: **Account**
(current content, default) and **Usage**. The Usage tab is a link to `/profile/usage`
(separate Inertia page) rather than an in-place panel, because the analytics props
are deferred and belong to a different controller action. Minimal change: add a
`Tabs` header at the top of `ProfilePage` (`Show.tsx:702-792`); the Usage tab uses
`onChange` → `router.visit(profileUsagePath())` (import from `shared/routes`). Keep
`maw={600}` only for the Account tab; the Usage page uses full width like the
analytics pages.

> Alternative considered: render Usage inline inside `Show` via `<Deferred>` with
> props provided by `#show`. Rejected because it bloats `#show` and mixes two defer
> groups on one page; a dedicated route matches the company/project analytics
> precedent and keeps each page's tests focused.

#### New: `app/frontend/shared/ui/ContributionHeatmap.tsx` (reusable — profile AND project)

A dependency-free GitHub-style calendar grid. Props: `days: { date: string; count: number }[]`
(from the `activity_heatmap` prop) and optional `weeks` (default 53). No Recharts —
render a CSS-grid / flex of week columns × 7 day rows, each cell a small square colored
by an **intensity bucket** derived from `count` (e.g. 0 / 1–2 / 3–5 / 6–9 / 10+ mapped
to five `--app-*` theme greens), with a Mantine `Tooltip` per cell ("{count} sessions
on {date}"). Because there is **no existing heatmap/calendar component** anywhere in
the FE (grep found none), this is net-new and lives in `shared/ui` so both pages import
it. Gap-filling is internal: build the full date range from `today - weeks*7` to
`today`, index the incoming `days` by ISO date, default missing dates to `count: 0`.
The component is presentational (no `usePage`), so it drops straight into both pages.

#### New: `app/frontend/pages/Profile/Usage.tsx`

Port the relevant panels from `Company/Analytics/AnalyticsPage.tsx`, add the heatmap
and a sessions table, and support the cross-person banner. **Important nuance:** only
the **module-level helpers** are genuinely reusable verbatim. Every *panel component*
(`SummaryPanel:170`, `ProjectBreakdownPanel:206`, `AgentActivityPanel:283`,
`CostTokenPanel:392`) internally calls
`usePage<{ props: Props }>().props as unknown as Props` against the **company** `Props`
interface, which includes `scope: Scope` (`Company/Analytics/AnalyticsPage.tsx:77-84`).
The new `Profile/Usage` `Props` has no `scope`, so each panel must be **re-typed against
the new `Props`** (a copy + retype). The JSX bodies are otherwise the same.

- **Reuse verbatim (module-level helpers only):** `formatCostCents:117`,
  `formatTokens:123`, `tickIntervalForPeriod:140`, `chartTooltipStyle:109`, the color
  arrays `AGENT_COLORS`/`PROJECT_COLORS` (`:86-99`) + `getAgentColor:100`,
  `PERIOD_OPTIONS:102`. `buildActivityChartData:130` is **not** reused (we drop the
  per-day-per-agent area trend; the heatmap replaces it as the "activity over time" view).
- **Cross-person banner.** When `!viewerIsSelf`, render a header banner
  ("Viewing {targetUser.name}'s usage") using the `target_user`/`viewer_is_self` props.
  Self-view hides it. This is the one visible difference from the project analytics port.
- `ContributionHeatmap` — fed by the `activityHeatmap.days` prop, wrapped in
  `<Deferred data="activity_heatmap" fallback={<Skeleton height={140} />}>`. Placed near
  the top (GitHub puts the calendar first). Satisfies the "activity/contribution
  heatmap in the user profile" AC.
- `SummaryPanel` — 5 stat cards (`Total Sessions / Total Cost / Total Tokens /
  Avg Cost / Workflows Run`), JSX as `:170-204`, re-typed to the new `Props`.
- `ProjectBreakdownPanel` — the per-project table, JSX as `:206-281`, re-typed. **One
  required change beyond re-typing:** the company panel uses `key={p.projectId}`
  (`:238`); the "(No project)" bucket has `projectId === null`, so key on a fallback
  (`key={p.projectId ?? 'none'}`). This is the AC "per-project contribution" deliverable.
- `AgentActivityPanel` — keep only the **pie + legend** (right `Grid.Col` at `:329-387`,
  consumes only `sessionsByAgent`). Drop the area-trend half (`:298-326`). Because the
  new `agentActivity` prop omits `activityOverTime`/`agentTypes`, also **remove** the
  `buildActivityChartData(agentActivity)` call (`:287`) and drop `agentTypes` from the
  destructure at `:288` — otherwise it throws on `undefined.activityOverTime` /
  `agentTypes.map`. Satisfies the "agent type breakdown" AC.
- `CostTokenPanel` — the two area charts (Daily Cost, Daily Token Consumption), JSX as
  `:392-466`, re-typed (reads `costToken.timeSeries`, preserved). Cost/token over time.
- **Sessions table** — port the `Session` row interface (`Company/Sessions/Index.tsx:11-33`),
  the columns (`:234-246`), and `SessionRow` (`:263-362`) from the company sessions
  page, wrapped in `<Deferred data="sessions">`. The `sessions` prop is an
  `inertia_scroll` payload of `TerminalSessionResource` rows scoped to the target user
  (§4 controller), so the same `InfiniteScroll` + `SessionRow` rendering applies. Drop
  the company page's `User` filter column semantics (rows are all one user) but keep the
  token/cost/status columns. Satisfies the "sessions list in the profile" AC.
- Period `Select` in the header; **no** `SegmentedControl`. When `!viewerIsSelf`, keep
  `user_id` in the query so navigation preserves the target. Optionally a project
  `Select` to drill into one project (maps to `project_id`) — gated on OQ-2.
- `navigateWithFilters` → `router.get(window.location.pathname,
  { period, ...(userId ? { user_id: userId } : {}), ...(projectId ? { project_id: projectId } : {}) },
  { preserveState:true, preserveScroll:true })`.

Props interface (hand-written — see "Types" below):

```ts
interface Props {
  period: '7d' | '30d' | '90d' | '1y';
  projectId?: string | null;
  viewerIsSelf: boolean;
  targetUser: { id: number; name: string | null; email: string };
  summary?: { totalSessions: number; totalCostCents: number; totalTokens: number;
              avgCostCentsPerSession: number; workflowsRun: number;
              // projectId is null for the "(No project)" bucket; key the row on
              // (projectId ?? 'none'), not key={p.projectId} as the company panel does (AnalyticsPage.tsx:238).
              projectBreakdowns: { projectId: number | null; projectName: string; sessions: number; costCents: number; tokens: number }[]; };
  agentActivity?: { sessionsByAgent: { agentType: string; sessions: number; costCents: number; tokens: number }[] };
  costToken?: { timeSeries: { date: string; costCents: number; totalTokens: number }[] };
  activityHeatmap?: { days: { date: string; count: number }[] };
  sessions?: Session[];   // inertia_scroll payload of TerminalSessionResource rows (Company/Sessions/Index.tsx:11-33)
}
```

#### Changed: `app/frontend/pages/Projects/Analytics/AnalyticsPage.tsx` — heatmap + participant filter

- Import and render `ContributionHeatmap` fed by a new `activityHeatmap?: { days: {...}[] }`
  prop, wrapped in `<Deferred data="activity_heatmap">`. Shows **all participants** by
  default. This is the "heatmap in the project view" AC.
- Add a **participant `Select`** in the header next to the existing period `Select` and
  the `scope` `SegmentedControl` (`:839-847`), populated from a new non-deferred
  `participants: { id; name; email }[]` prop. Choosing a participant sets a
  `participant_id` query param (via the page's existing `navigateWithFilters`, extended
  to carry `participant_id`); clearing it returns to all-participants. The pre-existing
  `scope=user` ("My Activity") toggle is untouched and orthogonal.
- Add `activityHeatmap`, `participants`, `participantId` to this page's hand-written
  `Props` (`:108-118`). No change to the six existing panels' contracts.

#### Hooks — none new

No custom hook is needed; the page uses `usePage`/`Deferred`/`router` exactly like
`Company/Analytics/AnalyticsPage.tsx:1`. (Optionally extract the shared
`formatCostCents`/`formatTokens`/`tickIntervalForPeriod` into a small
`shared/lib/analyticsFormat.ts` to avoid copy-paste between the three analytics
pages — nice-to-have, not required.)

#### Types — **not** Typelizer-generated (except the reused `Session` row)

Important: the analytics payloads are camelCased **inline in the controller**, not
serialized through an Alba resource, so they do **not** appear in `@/types/generated`
(`config/initializers/typelizer.rb:8-9`). Both existing analytics pages hand-write
their `interface SummaryData` etc. (`Company/Analytics/AnalyticsPage.tsx:24-84`,
`Projects/Analytics/AnalyticsPage.tsx:31-118`). `Profile/Usage.tsx` follows the same
convention: hand-write `Props`, `activityHeatmap`, `targetUser`, and (reuse the
`Company/Sessions/Index.tsx:11-33` `Session` row shape verbatim, since the `sessions`
prop serializes the same `TerminalSessionResource`). **Do not** add the analytics
payloads to generated types and **do not** edit anything under `@/types/generated`.

### Data migration (optional, idempotent)

No migration is required for correctness. `terminal_sessions` already has three
`user_id`-leading indexes — `index_terminal_sessions_on_user_id_and_session_type`
(`db/schema.rb:670`), `index_terminal_sessions_on_user_id_and_state` (`:671`), and
`index_terminal_sessions_on_user_id` (`:672`) — but **none** leads with
`(user_id, created_at)`, which is the exact filter the per-user, in-period
group-bys use. For query performance of the time-series and per-project group-bys
filtered by `(user_id, created_at)`, add a composite index:

```ruby
# db/migrate/XXXXXXXXXXXXXX_add_user_created_index_to_terminal_sessions.rb
class AddUserCreatedIndexToTerminalSessions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!
  def change
    add_index :terminal_sessions, %i[user_id created_at],
              name: "index_terminal_sessions_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :workflow_runs, %i[user_id created_at],
              name: "index_workflow_runs_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
```

Idempotency: `if_not_exists: true` makes re-runs safe; `algorithm: :concurrently`
(+ `disable_ddl_transaction!`) avoids a write lock on the hot `terminal_sessions`
table. This is a schema migration, not a data backfill — there is no row mutation,
so it is trivially idempotent. **Decision:** include it; the existing `user_id`-leading
indexes (`:670-672`) cover equality lookups by `user_id`/`session_type`/`state`, and
the planner can still use the plain `user_id` index for `scope=user` on one project,
but a personal cross-project time series filters by `(user_id, created_at)` over all of
a user's sessions and benefits from a composite whose second column matches the range
predicate. Flagged as low-priority (OQ-5) if the team prefers to defer indexing.

## 5. Edge Cases & Decisions

- **Session types in scope.** DECISION: include only `agent_session` and
  `workflow_step` (`USAGE_SESSION_TYPES`). Excluding `auth_setup`/`tool_setup`
  (a) keeps session counts meaningful, (b) avoids a "(no project)" bucket because
  those are the project-less rows (`terminal_session.rb:13`). → **OQ-1**: confirm PM
  wants auth/tool-setup excluded from "Sessions launched".
- **Project-less sessions in the breakdown.** DECISION: `build_project_breakdowns`
  uses `left_joins(:project)`, NOT the company service's inner `joins(:project)`.
  Restricting to billable session types (OQ-1) removes `auth_setup`/`tool_setup`
  noise but does **not** make every in-scope row have a project: an `agent_session`
  or `workflow_step` can still carry `project_id = nil`
  (`app/models/terminal_session.rb:13`, `app/services/session_service.rb:5`/`:141`,
  `test/factories/terminal_sessions.rb:43-45`). An inner join would silently drop
  those rows and break reconciliation
  (`sum(projectBreakdowns.sessions) < total_sessions`). The LEFT JOIN groups them into
  a single **"(No project)"** bucket (`projects.id IS NULL`), so the breakdown sums
  (sessions, cost, tokens) reconcile exactly with the summary totals. This is enforced
  by a dedicated reconciliation test in §7. (Alternative considered and rejected:
  `where.not(project_id: nil)` to exclude project-less rows from *both* summary and
  breakdown — also reconciles, but it under-counts the user's real "sessions launched"
  and is rejected for v1.)
- **Avg cost per session** uses **total** in-scope session count as denominator
  (matches `CompanyAnalyticsService:33`), so it can differ from
  `sum(project_breakdowns.cost)/sum(project_breakdowns.sessions)` — consistent with
  existing behavior.
- **Tokens fallback.** The `COALESCE(NULLIF(sum(breakdown),0), sum(tokens),0)`
  expression is reused verbatim, so older rows with only the legacy `tokens` column
  still count (cf. `workflow_cost_analytics_service_test.rb:128-146`).
- **Cross-person authorization (NEW, DECIDED).** Any authenticated **same-company**
  member may view another member's activity — **not** admin-gated. Enforced by
  `resolve_target_user` = `current_user.company.users.find(params[:user_id])`; a
  foreign or unknown `user_id` → `RecordNotFound` → 404. `user_id` absent → `current_user`
  (self-view unchanged). Precedent: `ProjectsPolicy#current_project` scopes finds to
  `current_user.company.projects` (`projects_policy.rb:24-27`). This is intentionally
  more permissive than an admin gate; the ethics guardrail (research §3.4) is met by
  self-visibility + same-company transparency, and by the metric being launched
  sessions (activity, not surveillance). → **OQ-6** (accept the same-company-any-member
  policy, and confirm no Pundit object is needed).
- **super_admin.** A `super_admin` has `company_id = nil` and is redirected to the
  admin panel by `redirect_super_admin_to_admin_panel` (`application_controller.rb:48-50`),
  so they never reach `/profile/usage`. If somehow reached, `current_user.company.users`
  would raise on the nil company — acceptable because the path is unreachable; no
  special handling. (A super_admin also cannot be a *target*, since targets are looked
  up inside a real company.)
- **Metric = launched sessions; workflow-run treatment (DECIDED).** The heatmap and the
  `total_sessions` count both count `agent_session` + `workflow_step`
  (`USAGE_SESSION_TYPES`), excluding `auth_setup`/`tool_setup`. Workflow runs are shown
  as a separate `workflows_run` headline but are **not** double-counted, because each
  executed workflow step already materializes as a `workflow_step` session
  (`session_service.rb:44-73`) that the session count includes. So a heavy workflow user
  sees both their `workflows_run` and the (larger) `workflow_step` session count. → OQ-1.
- **Heatmap counts null-`agent_type` rows (DECIDED).** `ActivityHeatmapService` does
  **not** re-apply `activity_over_time`'s `agent_type IS NOT NULL` filter
  (`agent_activity_service.rb:53`) — `workflow_step` sessions can have a null
  `agent_type` and must still appear on the calendar as launched sessions. This is a
  deliberate divergence from the agent-activity series.
- **Heatmap window vs period.** The contribution grid always renders a fixed ~53-week
  window (like GitHub) regardless of the `period` filter, so it reads as a year at a
  glance; the period `Select` drives the summary/breakdown/time-series panels. (If PM
  wants the heatmap to track `period`, it is a one-line `days:` change — noted, not
  gated.)
- **Project participant filter (DECIDED).** All participants by default; a `Select`
  from `project.member_users` (`project.rb:95-98`) sets `participant_id` to filter to
  one. Orthogonal to the existing `scope=user` ("My Activity") toggle, which is
  preserved unchanged.
- **Period default & unknown values.** `PERIOD_DAYS.fetch(period, 30)` /
  `DATE_TRUNC_KEY.fetch(period, "day")` default safely; unknown `?period=foo` → 30d/day.
- **Empty state.** With no sessions, `summary.totalSessions == 0`,
  `projectBreakdowns == []` (`ProjectBreakdownPanel` returns null on empty,
  `Company/Analytics/AnalyticsPage.tsx:208`), `activityHeatmap.days == []` (heatmap
  renders an all-level-0 grid via internal gap-fill), and the sessions table shows an
  empty scroll. Page degrades cleanly.
- **Sessions list scope.** The profile sessions prop scopes to
  `target.terminal_sessions` and excludes `auth_setup` (mirror `sessions_controller.rb:9`),
  reusing `TerminalSessionResource` + `inertia_scroll`. It does **not** reuse
  `company_sessions_scope` (company-wide); the point is one user's sessions.
- **`scope=user` regression risk.** The project page's "My Activity" toggle and all
  six project/company services keep working; the project changes are **additive** (a
  new heatmap prop, a participant `Select`/param, optionally threading `participant_id`
  through `scope_sessions`). AC "My Activity continues to work" is satisfied by
  non-modification of the toggle + a regression test (§7).

OPEN QUESTIONS (updated — what is now DECIDED vs still open):

DECIDED (baked into this revision):
- **Cross-person = any same-company member, not admin-gated** (§5). Only the "should we
  also expose a Pundit object" nuance remains (OQ-6).
- **Metric = launched sessions** (`agent_session` + `workflow_step`), workflow runs
  shown separately, not double-counted (§1, §5) — modulo OQ-1 confirmation.
- **Heatmap in both profile and project views**, one reusable `ContributionHeatmap` +
  one reusable `ActivityHeatmapService`, no charting dependency (§3, §4).
- **Project view: all participants by default + participant `Select`** (§3, §4, §5).
- **Sessions list on the profile**, reusing `TerminalSessionResource`/`inertia_scroll`,
  scoped to the target user (§3, §4).
- **Three slice-specific services** (was OQ-4) — decided; only the "accept extra files"
  confirmation remains.

STILL OPEN:
- **OQ-1** Confirm "Sessions launched" excludes `auth_setup`/`tool_setup` (design
  assumes yes; matches the Company/Sessions index exclusion `sessions_controller.rb:9`).
- **OQ-2** Ship the per-project **drill-down** `Select` (`project_id` param) on the
  profile Usage view in v1, or only the read-only breakdown table? (service supports both.)
- **OQ-3** Explicit input/output/cache **token-split** chart, or total-token parity with
  the company page for v1? (Affects `TimeSeriesPoint`/`SummaryData` columns.)
- **OQ-4** Confirm the team accepts three extra service files for the faithful,
  lower-cost mirror (recommended; no recomputation across deferred blocks).
- **OQ-5** Add the composite `(user_id, created_at)` indexes now or defer.
- **OQ-6** Accept "any same-company member may view any member" (no admin gate) and "no
  Pundit object, controller scope guard only" for the usage action.
- **OQ-7** Should the **project view honor `participant_id` on all six panels** in v1,
  or only the heatmap (with panel-level participant filtering as a fast follow)? The
  heatmap needs it; extending the other services' `scope_sessions` is additive.
- **OQ-8** Should the profile sessions list gain ransack **filters** (agent/status) like
  the company page in v1, or ship as a plain scoped list first?

## 6. Acceptance Criteria Mapping

| AC (from expanded scope) | Satisfied by |
| --- | --- |
| Profile page has a "Usage" tab | `Profile/Show.tsx` `Tabs` header → "Usage" tab linking to `/profile/usage`; route `get :usage` on `resource :profile` (`config/routes.rb:186`). |
| Usage view shows session count, workflow runs, total tokens, total cost for the period | `UserAnalyticsService#call` → `total_sessions / workflows_run / total_tokens / total_cost_cents`; `Profile/Usage.tsx` `SummaryPanel` (ported from `Company/Analytics/AnalyticsPage.tsx:170-204`). |
| Metrics filterable by time period | `period` param → `PERIOD_DAYS`/`DATE_TRUNC_KEY`; header `Select` `7d/30d/90d/1y` (`PERIOD_OPTIONS`, `:102-107`). |
| Per-project breakdown table | `UserAnalyticsService#build_project_breakdowns` (left-join + "(No project)") → `projectBreakdowns`; `ProjectBreakdownPanel` (`:206-281`). |
| Agent type breakdown | `UserAgentActivityService` → `sessionsByAgent`; agent pie panel. |
| **GitHub-style activity/contribution heatmap in the profile** | `ActivityHeatmapService.new(scope: target.terminal_sessions)` → `activity_heatmap` prop; reusable `shared/ui/ContributionHeatmap.tsx` on `Profile/Usage.tsx`. |
| **GitHub-style heatmap in the project view** | `ActivityHeatmapService.new(scope: project.terminal_sessions)` → `activity_heatmap` deferred prop on `projects/analytics_controller.rb`; same `ContributionHeatmap` on `Projects/Analytics/AnalyticsPage.tsx`. |
| **Cross-person: any member views another same-company member's activity** | `Web::ProfileController#usage` `resolve_target_user` = `current_user.company.users.find(params[:user_id])` (404 for foreign id); services keyed off the resolved `target`. Not admin-gated. |
| **Self (personal) view still works** | `user_id` absent → target defaults to `current_user`; `viewer_is_self: true` hides the banner. |
| **Project view: all participants by default, filterable by one** | `activity_heatmap`/panels default to `project.terminal_sessions`; participant `Select` from `project.member_users` (`project.rb:95-98`) sets `participant_id` → `where(user_id: participant_id)`. |
| **Sessions list in the profile scoped to the target user** | `sessions` deferred prop = `target.terminal_sessions` (excl. `auth_setup`) via `inertia_scroll` + `TerminalSessionResource`; sessions table ported from `Company/Sessions/Index.tsx`. |
| Activity over time (cost/tokens) | `UserSessionCostTokenUsageService` → `costToken.timeSeries`; daily cost/token area charts (`:392-466`). |
| "My Activity" project scope keeps working | The `scope=user` `SegmentedControl` (`Projects/Analytics/AnalyticsPage.tsx:839-847`) and `ProjectAnalyticsService` are unchanged; project changes are additive. Guarded by a regression test (§7). |
| Reconciliation: per-project contributions sum to totals | `left_joins(:project)` + "(No project)" bucket in `build_project_breakdowns`; enforced by the §7 reconciliation test. |

## 7. Test Plan

### Service unit test — NEW `test/services/user_analytics_service_test.rb`

Mirror `test/services/workflow_cost_analytics_service_test.rb` structure (FactoryBot,
`assert { ... }` style). Note `CompanyAnalyticsService` itself has **no** unit test
(there is no `company_analytics_service_test.rb`), so the closest existing service-test
templates are `session_cost_token_usage_service_test.rb`,
`session_source_breakdown_service_test.rb`,
`session_duration_distribution_service_test.rb`, and
`workflow_cost_analytics_service_test.rb` — mirror their seeding/`assert` style. Cases:

- Aggregates only the given user's sessions across **multiple** projects; another
  user's sessions in the same projects are excluded.
- `project_breakdowns` has one row per project the user has sessions in, ordered by
  cost desc, summing to the summary totals.
- **Reconciliation invariant (the test that catches the project-less bug):** seed a
  user with at least one project-bound `agent_session` AND one **project-less**
  `agent_session` (`project: nil`), each with a `UsageStatistic`. Assert
  `result.project_breakdowns.sum(&:sessions) == result.total_sessions`,
  `sum(&:cost_cents) == result.total_cost_cents`, and
  `sum(&:tokens) == result.total_tokens`. Assert exactly one breakdown row has
  `project_id == nil` / `project_name == "(No project)"` and that it carries the
  project-less session's session count and cost. This directly exercises the AC
  "per-project contribution to the totals" and fails if `build_project_breakdowns`
  regresses to an inner join.
- Period window excludes rows older than `period` (build a session at `60.days.ago`,
  assert absent for `30d`) — mirrors
  `workflow_cost_analytics_service_test.rb:56-63`.
- `total_tokens` legacy fallback: a `UsageStatistic` with zero breakdown but
  `tokens: 500` counts as 500 — mirrors `:128-146`.
- `auth_setup`/`tool_setup` sessions are excluded from counts and breakdown (OQ-1
  decision).
- `agent_breakdowns` groups by `agent_type`, ignores `agent_type IS NULL`
  (workflow_step sessions may set agent_type; auth excluded anyway). Use a **valid**
  `agent_type` from `claude_code|cursor_cli|codex|gemini_cli`
  (`terminal_session.rb:40-43`) — do not copy the company test's invalid `'coding'`.
- (in `UserSessionCostTokenUsageService`) `time_series` bucket granularity:
  `7d`→daily points, `1y`→monthly points (mirror `:106-124`); each `date` matches
  `\A\d{4}-\d{2}-\d{2}\z`.
- `project_id:` argument restricts all metrics to that project.

Seeding mirrors the company test: `build(:terminal_session, ...).save!(validate: false)`
then `UsageStatistic.create!(...)` (cf.
`test/integration/web/company/analytics_controller_test.rb:48-58`), or the factory
chain in `workflow_cost_analytics_service_test.rb:16-31`. **Caveat on seeded
`agent_type`:** the company integration test uses `agent_type: "coding"` with
`save!(validate: false)` (`analytics_controller_test.rb:50`), which is **invalid** per
`terminal_session.rb:40-43` (only `claude_code|cursor_cli|codex|gemini_cli`). Seed a
real `agent_type` here so the `agent_breakdowns` assertions are meaningful.

### Service unit test — NEW `test/services/activity_heatmap_service_test.rb`

- Groups the scope's sessions into one `{date, count}` per calendar day; two sessions
  on the same UTC day collapse to `count: 2`.
- Counts `workflow_step` sessions **even when `agent_type` is nil** (the divergence from
  `activity_over_time`) — seed a `workflow_step` with `agent_type: nil` and assert it
  appears on the day's count.
- Excludes `auth_setup`/`tool_setup` sessions.
- Window: a session older than `days` is absent; `date` matches `\A\d{4}-\d{2}-\d{2}\z`.
- Scope agnosticism: same service, given `user.terminal_sessions`,
  `project.terminal_sessions`, and `project.terminal_sessions.where(user_id:)`, returns
  the correctly-scoped counts (parametrize the three callers).

### Request/integration test — NEW `test/integration/web/profile_usage_controller_test.rb`

> An existing `test/integration/web/profile_controller_test.rb`
> (`class Web::ProfileControllerTest`) already covers `#show`/`#update`. DECISION:
> keep the usage tests in a separate `Web::ProfileUsageControllerTest` file (focused,
> deferred-prop assertions) rather than consolidating into the existing class. Either
> way, the setup **must** match the convention both existing suites use.

**Required setup (must-fix — the page redirects otherwise):** `Web::ProfileController`
inherits two `before_action`s from `Web::ApplicationController`:
`redirect_super_admin_to_admin_panel` (`:8`, `:48-50`) and `enforce_onboarding`
(`:9`, `:52-57`). The latter redirects any signed-in user whose
`onboarding_state != "completed"` to `onboarding_path`, so a default `create(:user)`
would be bounced to onboarding before reaching `Profile/Usage`. Sign in as a
**non-super_admin, onboarding-completed** user, exactly like the existing suites:
`create(:user, :admin, :onboarding_completed, company:, password: AuthHelper::TEST_PASSWORD)`
then `sign_in_as(@user)` (cf. `profile_controller_test.rb:8`,
`company/analytics_controller_test.rb:8`). (`:admin` keeps the role off
`super_admin`, which would otherwise be redirected to `admin_root_path` by
`redirect_super_admin_to_admin_panel`.)

Mirror `test/integration/web/company/analytics_controller_test.rb`:

- `GET /profile/usage` renders `"Profile/Usage"`, `assert_inertia_props period: "30d",
  viewer_is_self: true` and `target_user` = the signed-in user.
- Passes custom `?period=7d`.
- `assert_inertia_deferred_props :summary, :agent_activity, :cost_token,
  :activity_heatmap, :sessions, group: "usage"`.
- After `inertia_load_deferred_props("usage")`, empty user → `summary` zeros,
  `projectBreakdowns: []`, `activity_heatmap.days == []`, `sessions == []` (mirror `:32-46`).
- With seeded session + `UsageStatistic`, asserts real `totalSessions/totalCostCents/
  totalTokens`, one `projectBreakdowns` row, one `activity_heatmap.days` entry, and one
  `sessions` row. Seed a **valid** `agent_type` (`claude_code` etc.).
- **Reconciliation across the controller boundary:** seed a project-bound and a
  project-less `agent_session`, load deferred props, assert
  `summary.projectBreakdowns.sum { |p| p[:sessions] } == summary.totalSessions` (and for
  `costCents`/`tokens`) with one `projectName == "(No project)"` row.
- **Cross-person (same company, allowed):** `create(:user, :onboarding_completed, company:)`
  as user B with a seeded session; sign in as user A in the **same** company; `GET
  /profile/usage?user_id=B.id` renders with `viewer_is_self: false`, `target_user.id ==
  B.id`, and after loading deferred props the `summary`/`sessions` reflect **B's** data,
  not A's. (No admin role required for A — asserts the "any member" requirement.)
- **Cross-person (different company, forbidden):** user C in a **different** company;
  `GET /profile/usage?user_id=C.id` as user A → 404 (`RecordNotFound` from
  `current_user.company.users.find`), never leaking C's data.
- **Self-default:** `GET /profile/usage` (no `user_id`) targets the requester.
- **super_admin is redirected:** `create(:user, :super_admin, ...)`, `GET /profile/usage`
  → `admin_root_path` (`application_controller.rb:48-50`).
- Unauthenticated `GET /profile/usage` → `login_path` (`require_auth`,
  `profile_controller.rb:6`).

### Request/integration test — MODIFY `test/integration/web/company/projects/analytics_controller_test.rb`

- `assert_inertia_deferred_props` now includes `:activity_heatmap` (group `"analytics"`);
  a non-deferred `participants` prop lists `project.member_users`.
- All participants by default: two participants each with sessions → the heatmap and
  panels reflect both.
- `?participant_id=<one>` narrows the heatmap (and, per OQ-7 decision, the panels) to
  that participant only; another participant's sessions are excluded.
- Regression: the six existing deferred props and the `scope=user` toggle still behave
  as before.

### Frontend test — NEW `app/frontend/pages/Profile/Usage.test.tsx`

Mirror `app/frontend/pages/Company/Analytics/AnalyticsPage.test.tsx` (Vitest + jsdom,
`renderAuthedPage`):

- Renders summary stat values once `summary` prop is present (formatting:
  `1,234`, `$567.89`, `2.5M`).
- Renders per-project rows when `summary.projectBreakdowns` present; hides the panel
  when empty (mirror `:80-88`, `:156-166`).
- Renders a **"(No project)"** row when a breakdown entry has `projectId: null`, and
  the component does not crash (verifies the `key={p.projectId ?? 'none'}` fallback,
  since two null-id rows would otherwise collide on React keys).
- Agent pie legend shows sessions + formatted cost per agent type (mirror `:168-183`).
  The ported `AgentActivityPanel` renders **only** the pie+legend and does **not**
  reference `agentActivity.activityOverTime`/`agentTypes` — assert it renders with an
  `agentActivity` prop that omits those keys.
- Renders the `ContributionHeatmap` when `activityHeatmap.days` is present (assert a
  cell for a seeded date shows the count in its tooltip); renders an all-zero grid when
  `days: []` (empty state).
- Renders the sessions table rows from the `sessions` prop (reuse the company
  `SessionRow` assertions).
- **Cross-person banner:** with `viewerIsSelf: false` + a `targetUser`, the banner
  ("Viewing {name}'s usage") renders; with `viewerIsSelf: true` it is absent.
- Period `Select` change calls `router.get(pathname, { period, ...(user_id when not
  self) }, {preserveState, preserveScroll})` (mirror `:116-132`, adapted).
- Skeletons show and panels are absent while deferred props are undefined
  (mirror `:101-114`).

### Frontend test — NEW `app/frontend/shared/ui/ContributionHeatmap.test.tsx`

- Given `days` with varied counts, renders one cell per day in the window and assigns
  the expected intensity-bucket class per count threshold (0 / low / high).
- Gap-fills: days absent from `days` render as level-0 cells (assert total cell count ==
  `weeks * 7`, not `days.length`).
- Tooltip text per cell includes the count and date.

### Frontend test — MODIFY `app/frontend/pages/Profile/Show.test.tsx`

- The page renders an "Account" tab and a "Usage" tab; existing settings assertions
  still pass under the default (Account) tab.
- Clicking "Usage" calls `router.visit('/profile/usage')` (spy `router`).

### Frontend test — MODIFY `app/frontend/pages/Projects/Analytics/AnalyticsPage.test.tsx`

- Renders the `ContributionHeatmap` when `activityHeatmap` is present.
- The participant `Select` (from `participants`) renders; choosing one calls
  `router.get(pathname, { ..., participant_id }, ...)`; the existing `scope`
  `SegmentedControl` still renders and toggles unchanged (protects the "My Activity" AC).

## 8. Risks & Rollout

- **Query cost.** Personal cross-project aggregation scans all of a user's
  in-period sessions. Mitigation: the optional composite indexes (§4 migration) and
  the same LEFT-JOIN-on-`usage_statistics` pattern the company page already runs in
  production. Low risk at current data volumes; if it grows, introduce a nightly
  rollup table (deferred per §3 rejected alternatives).
- **Cross-person data leak (the highest-severity new risk).** The usage action now
  accepts a `user_id`. The classic IDOR is leaking another company's user. Mitigation:
  `resolve_target_user` looks the target up **inside** `current_user.company.users`
  (scope-before-find), so a foreign id is a 404, never a leak. This is covered by the
  "different company → 404" integration test. Because the feature is deliberately
  **not** admin-gated, the same-company boundary is the *only* guard and must be
  correct — hence the dedicated test.
- **Ethics of cross-person visibility.** Per research §3.4, per-person activity is
  industry-normal (Anthropic ships a per-user Claude Code Analytics API), and this
  feature stays on the safe side by using launched-sessions activity (not surveillance
  signals) and keeping it same-company/self-visible. Still a product posture to confirm
  (the metric is activity, not a productivity/leaderboard score) — noted, not gating.
- **Heatmap correctness.** Two subtleties: (a) it must **not** re-apply the
  `agent_type IS NOT NULL` filter or `workflow_step` sessions vanish; (b) gap-fill is in
  the component, so an empty series must still render a full grid. Both are covered by
  the heatmap service + component tests.
- **Recomputed aggregation across deferred blocks (resolved).** The three-service split
  means each deferred block runs only its own query — no ~3x recompute. (If a reviewer
  insists on one file, expose per-metric methods.)
- **Token-split scope creep (OQ-3).** The explicit input/output/cache chart is additive
  (extra time-series columns + one chart) and does not change the rest of the design.
- **No schema risk.** No table/column changes; the only DDL is `CREATE INDEX
  CONCURRENTLY ... IF NOT EXISTS`, lock-free and idempotent.
- **Surface area.** New files: three user analytics slice services
  (`UserAnalyticsService` + `UserAgentActivityService` + `UserSessionCostTokenUsageService`),
  `ActivityHeatmapService`, `shared/ui/ContributionHeatmap.tsx`, `Profile/Usage.tsx`,
  and their tests. Small edits: a member route line, one `ProfileController#usage`
  action, a tabbed header on `Show.tsx`, additive changes to
  `projects/analytics_controller.rb` + `Projects/Analytics/AnalyticsPage.tsx` (heatmap
  prop + participant `Select`/param), and (if added) a one-line `WorkflowRun` scope. The
  existing analytics services and the `scope=user` toggle are **untouched**, protecting
  "My Activity continues to work."
- **Rollout.** Ship behind no flag (read-only, no destructive paths). Verify in staging
  by (1) signing in as a user with sessions across ≥2 projects and confirming per-project
  totals reconcile with each project's own `scope=user` page; (2) viewing a **teammate's**
  `/profile/usage?user_id=…` in the same company (allowed) and a foreign user (404);
  (3) confirming the profile and project heatmaps render the same day counts for a shared
  session set. Run Rails/Vitest suites in Docker (`docker compose exec -T web ...`).
