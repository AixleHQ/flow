# Frontend Rewrite: Inertia.js + Mantine — Plan and Tracking

> Migration: TanStack Router + RTK Query + MUI + Axios → Inertia.js + Mantine + Alba + Typelizer
> Start: April 2, 2026
> Detailed comparison: [frontend-stack-comparison.md](../frontend-stack-comparison.md)

---

## Scale

| Metric | Value |
|---------|---------|
| .ts + .tsx files | ~335 |
| Pages | 24 |
| RTK Query API modules | 28 |
| AMS Serializers | 41 |
| ActionCable hooks | 5 |
| Feature modules | ~25 |

## Principles

1. **Incrementally** — the old SPA and Inertia run in parallel
2. **Bottom-up** — from simple pages to complex ones
3. **Everything new is Inertia only** — after phase 0, no page on the old stack
4. **Web scope** — all Inertia controllers in `Web::`, layout `"inertia"`
5. **ts_routes stays** — typed routes

---

## Phase 0: Infrastructure — 🟢 COMPLETED

> Goal: set up Inertia + Mantine + Alba + Typelizer. Old SPA unchanged.

| # | Task | Status |
|---|--------|--------|
| 0.1 | Gemfile: `inertia_rails` 3.19, `alba` 3.10, `typelizer` 0.12 | ✅ |
| 0.2 | `config/initializers/inertia.rb` — SSR off, default_render off, use_script_element | ✅ |
| 0.3 | `Web::ApplicationController` — `inertia_share` (current_user, flash) | ✅ |
| 0.4 | `app/resources/` — `ApplicationResource`, `CurrentUserResource`, `CompanyResource` | ✅ |
| 0.5 | `config/initializers/typelizer.rb` + `serializer_model_mapper` | ✅ |
| 0.6 | `rails typelizer:generate` → `CurrentUser.ts`, `Company.ts` with types from DB | ✅ |
| 0.7 | `yarn add @inertiajs/react @mantine/core @mantine/hooks @mantine/form @mantine/notifications @mantine/dates @tabler/icons-react dayjs` | ✅ |
| 0.8 | `app/frontend/entrypoints/inertia.tsx` — createInertiaApp + MantineProvider + Sentry | ✅ |
| 0.9 | `app/views/layouts/inertia.html.haml` — Gon + vite_javascript_tag "inertia.tsx" | ✅ |
| 0.10 | `shared/theme/mantineTheme.ts` — dark theme, palette from MUI, Poppins | ✅ |
| 0.11 | `layouts/InertiaAuthLayout.tsx` (AppShell + flash) + `InertiaGuestLayout.tsx` | ✅ |
| 0.12 | `Web::TestController` + route `/inertia-test` + `pages-inertia/Test/Show.tsx` | ✅ |
| 0.13 | Manual check in the browser (Playwright MCP) | ✅ |

**Nuances:**
- Typelizer computed attributes (`configured_agents`, `default_agent_runtime`) → `unknown`. Solution: `properties_transformer` or manual `typelize` after improving Alba compatibility.
- The `@inertiajs/vite` Vite plugin is not needed for Rails — `vite-plugin-ruby` is sufficient.

---

## Phase 1: Simple CRUD pages — 🟢 COMPLETED

> Goal: 5 simplest pages on Inertia + Mantine. Pattern: controller + Alba resource + Typelizer type + Mantine UI.

### 1.1 — Profile (`/profile`)

| # | Task | Status |
|---|--------|--------|
| 1.1.1 | Alba: `AgentCredentialResource` + extend `CurrentUserResource` | ✅ |
| 1.1.2 | `Web::ProfileController#show` — `render inertia: 'Profile/Show'` | ✅ |
| 1.1.3 | `Web::ProfileController#update` — `redirect_to` with flash | ✅ |
| 1.1.4 | Route: `get/patch "profile"` in web scope | ✅ |
| 1.1.5 | `pages-inertia/Profile/Show.tsx` — full copy (form, Default Agent, Agent Runtimes) | ✅ |
| 1.1.6 | UX fix: Default Models — Autocomplete → Select (searchable + clearable, full list) | ✅ |
| 1.1.7 | Remove old page `pages/profile/` + RTK `currentUserApi` mutations | ⬜ (during cleanup) |

### 1.2 — Company Members (`/company/members`)

| # | Task | Status |
|---|--------|--------|
| 1.2.1 | Alba: `UserResource` | ✅ |
| 1.2.2 | `Web::Company::MembersController` — index, create, update, destroy | ✅ |
| 1.2.3 | Routes: company/members GET/POST/PATCH/DELETE | ✅ |
| 1.2.4 | `pages-inertia/Company/Members/Index.tsx` — Table + search + action menu | ✅ |
| 1.2.5 | `InviteUserModal` — Mantine `Modal` + Inertia `useForm` | ✅ |
| 1.2.6 | Remove `pages/company-members/` + `companyUsersApi` | ⬜ (during cleanup) |

### 1.3 — Config Items (`/company/config-items`)

| # | Task | Status |
|---|--------|--------|
| 1.3.1 | Alba: `ConfigItemResource` | ✅ |
| 1.3.2 | `Web::Company::ConfigItemsController` — CRUD | ✅ |
| 1.3.3 | `pages-inertia/Company/ConfigItems/Index.tsx` — Table + Modal + Type filter | ✅ |
| 1.3.4 | Remove `pages/config-items/` + `configItemsApi` | ⬜ (during cleanup) |

### 1.4 — Integrations (`/company/integrations`)

| # | Task | Status |
|---|--------|--------|
| 1.4.1 | Alba: `IntegrationResource` | ✅ |
| 1.4.2 | `Web::Company::IntegrationsController` — index, destroy | ✅ |
| 1.4.3 | `pages-inertia/Company/Integrations/Index.tsx` — Card list + Badge + Connect menu | ✅ |
| 1.4.4 | Remove `pages/integrations/` + `integrationsApi` | ⬜ (during cleanup) |

### 1.5 — Repositories (`/company/repositories`)

| # | Task | Status |
|---|--------|--------|
| 1.5.1 | Alba: `RepositoryResource` | ✅ |
| 1.5.2 | `Web::Company::RepositoriesController` — CRUD | ✅ |
| 1.5.3 | `pages-inertia/Company/Repositories/Index.tsx` — Card list + Edit modal | ✅ |
| 1.5.4 | Remove `pages/repositories/` + `repositoriesApi` | ⬜ (during cleanup) |

**Criterion:** ✅ 5 pages on Inertia. All render, CRUD works. Removing legacy — in phase 6.

---

## Phase 2: CRUD + forms + modals — 🟢 COMPLETED

> Goal: migrate pages with nested forms, file upload, JSON editors.

### 2.1 — Agents (`/company/agents`)

| # | Task | Status |
|---|--------|--------|
| 2.1.1 | Alba: `AgentResource` | ✅ |
| 2.1.2 | `Web::Company::AgentsController` — CRUD | ✅ |
| 2.1.3 | UI: `Index.tsx` — Table + search + empty state | ✅ |
| 2.1.4 | UI: `AgentFormModal.tsx` — Create/Edit modal with EmojiPicker | ✅ |
| 2.1.5 | UI: `DeleteAgentModal.tsx` — Delete confirmation | ✅ |
| 2.1.6 | Mantine `EmojiPicker` (`shared/ui-inertia/EmojiPicker.tsx`) | ✅ |
| 2.1.7 | Remove `pages/agents/` + `agentsApi` | ⬜ (during cleanup) |

### 2.2 — Tools (`/company/tools`)

| # | Task | Status |
|---|--------|--------|
| 2.2.1 | Alba: `ToolResource`, `ToolFileResource` | ✅ |
| 2.2.2 | `Web::Company::ToolsController` — CRUD + nested tool_files | ✅ |
| 2.2.3 | UI: `Index.tsx` — Table + search + kind filter (SegmentedControl) | ✅ |
| 2.2.4 | UI: `ToolFormModal.tsx` — 3 tabs (Basic Info, Files, Config Items) | ✅ |
| 2.2.5 | UI: `ToolFileEditor.tsx` — CodeMirror with language detection | ✅ |
| 2.2.6 | UI: `DeleteToolModal.tsx` — Delete confirmation | ✅ |
| 2.2.7 | Remove `pages/tools/` + `toolsApi` | ⬜ (during cleanup) |

### 2.3 — Skills (`/company/skills`)

| # | Task | Status |
|---|--------|--------|
| 2.3.1 | Alba: `SkillResource` | ✅ |
| 2.3.2 | `Web::Company::SkillsController` — CRUD | ✅ |
| 2.3.3 | UI: `Index.tsx` — Table + search + kind badge + empty state | ✅ |
| 2.3.4 | UI: `SkillFormModal.tsx` — Create/Edit (name, title, content, description) | ✅ |
| 2.3.5 | UI: `DeleteSkillModal.tsx` — Delete confirmation | ✅ |
| 2.3.6 | Remove `pages/skills/` + `skillsApi` | ⬜ (during cleanup) |

### 2.4 — MCP Servers (`/company/mcp_servers`)

| # | Task | Status |
|---|--------|--------|
| 2.4.1 | Alba: `MCPServerResource` | ✅ |
| 2.4.2 | `Web::Company::MCPServersController` — CRUD | ✅ |
| 2.4.3 | UI: `Index.tsx` — Table + search + kind filter + scope/status/transport badges | ✅ |
| 2.4.4 | UI: `McpServerFormModal.tsx` — Transport-dependent fields (HTTP/SSE→URL+Headers, Stdio→Command+Env) + ConfigItemValueField + Enabled switch | ✅ |
| 2.4.5 | UI: `DeleteMcpServerModal.tsx` — Delete confirmation | ✅ |
| 2.4.6 | UI: `ConfigItemValueField.tsx` — Toggle between plain text and config item reference | ✅ |
| 2.4.7 | Remove `pages/mcp-servers/` + `mcpServersApi` | ⬜ (during cleanup) |

### ~~2.5 — Assets~~ → moved to 2.8

### 2.6 — Login (`/login`)

| # | Task | Status |
|---|--------|--------|
| 2.6.1 | `Web::SessionsController` — guest layout, Inertia render + error props | ✅ |
| 2.6.2 | UI: `Auth/LoginPage.tsx` — Mantine `Paper`, `TextInput`, `Button`, dark theme | ✅ |
| 2.6.3 | UI: `Auth/GoogleLoginButton.tsx` — Google OAuth link + SVG icon | ✅ |
| 2.6.4 | Error messages (pending_approval, deactivated, oauth_failed) + notifications | ✅ |
| 2.6.5 | Remove `pages/login/` + `loginApi` | ⬜ (during cleanup) |

### 2.7 — Onboarding (`/onboarding`) — ✅ COMPLETED (base version)

> Terminal auth (step 3) — Phase 4.

| # | Task | Status |
|---|--------|--------|
| 2.7.1 | `Web::OnboardingController` — show + update with AASM events | ✅ |
| 2.7.2 | Route: `resource :onboarding` | ✅ |
| 2.7.3 | UI: `Onboarding/OnboardingPage.tsx` — Stepper, 4 steps | ✅ |
| 2.7.4 | Step 1: Profile (position + language) | ✅ |
| 2.7.5 | Step 2: Select Agents (cards + checkboxes) | ✅ |
| 2.7.6 | Step 3: Authenticate (status display, skip) | ✅ |
| 2.7.7 | Step 4: Complete (summary + Get Started) | ✅ |
| 2.7.8 | Session redirect → onboarding if not completed | ✅ |
| 2.7.9 | Terminal auth integration (xterm.js + ActionCable) | ✅ (Phase 4.8) |

### 2.8 — Assets (`/company/assets` + `/company/projects/:id/assets`) — ✅ COMPLETED (table + preview)

> Uppy upload — Phase 4 (requires Uppy + presigned URLs).

| # | Task | Status |
|---|--------|--------|
| 2.8.1 | Alba: `AssetResource` | ✅ |
| 2.8.2 | `Web::Company::Projects::AssetsController` — index with assets | ✅ |
| 2.8.3 | `Web::Company::AssetsController` — company-level index | ✅ |
| 2.8.4 | Route: `resources :assets, only: :index` in company scope | ✅ |
| 2.8.5 | Shared: `AssetsContent` — Table + search + folder filter + preview modal | ✅ |
| 2.8.6 | UI: `Projects/Assets/AssetsPage.tsx` (project-scoped) | ✅ |
| 2.8.7 | UI: `Company/Assets/Index.tsx` (company-scoped) | ✅ |
| 2.8.8 | Upload via Uppy | ✅ (Phase 4.9) |

**Criterion:** ✅ 8 pages on Inertia (Agents, Tools, Skills, MCP Servers, Login + earlier Profile, Members, ConfigItems, Integrations, Repositories). All CRUD migrated. Onboarding and Assets — in Phase 3.

**Additionally (cross-cutting):**
- `Web::ApplicationController` — `before_action :redirect_super_admin_to_admin_panel` for automatic redirect of super_admin to `/admin`
- `Api::V1::SessionsController#omniauth` — super_admin redirect to `/admin` after OAuth
- Skills page — full CRUD tested via Playwright MCP (create, edit, delete, search)

---

## Phase 3: Complex pages + live data — 🟢 COMPLETED

> Goal: Project page with tabs, partial reloads, deferred props, kanban with ActionCable.

### 3.1 — Projects List (`/company/projects`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 3.1.1 | Alba: `ProjectResource` with statistics | ✅ |
| 3.1.2 | `Web::Company::ProjectsController#index` | ✅ |
| 3.1.3 | UI: Mantine `Card` grid + search + empty state | ✅ |
| 3.1.4 | Remove `pages/projects/` + `projectsApi` | ⬜ (during cleanup) |

### 3.2 — Project Page: infrastructure — ✅ COMPLETED

> Architecture: **each tab — a separate controller** (`Web::Company::Projects::*Controller`)
> with a shared `ProjectLayout` (AppHeader + AppSidebar + content). Resourceful routing.

| # | Task | Status |
|---|--------|--------|
| 3.2.1 | `Projects::ApplicationController` — base with `set_project`, `project_props` | ✅ |
| 3.2.2 | `ProjectLayout.tsx` — wrapper via `InertiaAuthLayout` (header+sidebar+content) | ✅ |
| 3.2.3 | Routes: nested `scope module: :projects` with resourceful routing | ✅ |
| 3.2.4 | `ProjectsController#show` → redirect to overview | ✅ |
| 3.2.5 | 16 placeholder tab controllers + Inertia pages | ✅ |
| 3.2.6 | Sidebar navigation via `router.visit` (Inertia) | ✅ |

### 3.3 — Tab: Settings (`/company/projects/:id/settings`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | `Projects::SettingsController` — show, update | ✅ |
| b | UI: `SettingsPage.tsx` — name + description form | ✅ |

### 3.4 — Tab: Members / Collaborators (`/company/projects/:id/members`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | `Projects::MembersController` — index (member_users + company_users), create (collaborator: user_id), destroy | ✅ |
| b | UI: `MembersPage.tsx` — avatar list + Owner badge + Add Collaborator (Select from company users) + Remove | ✅ |
| c | Separated from company Members — different logic (invite vs select existing) | ✅ |

### 3.5 — Tab: Overview (`/company/projects/:id/overview`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | `Projects::OverviewController` — calling 4 services (CompanyOverview, WorkflowRunStats, BoardTaskDistribution, RecentActivity) | ✅ |
| b | UI: Mantine `SimpleGrid` stat cards + Progress bars + Recent Activity list + Board distribution grid | ✅ |

### 3.6 — Tab: Board (Kanban) (`/company/projects/:id/board`) — ✅ COMPLETED (base version)

| # | Task | Status |
|---|--------|--------|
| a | Alba: `BoardResource`, `BoardColumnResource`, `BoardTaskResource` | ✅ |
| b | `Projects::BoardController` — index with board + columns + tasks + members | ✅ |
| c | `@dnd-kit` for drag-and-drop between columns | ✅ |
| d | Create Task modal (type, priority, assignee, column) | ✅ |
| e | Auto-create board from preset | ✅ |
| f | Sidebar with comments, assets, activity feed | ✅ (Phase 4.7) |
| g | ActionCable → `router.reload` | ✅ (Phase 4.7) |

### 3.7 — Tab: Workflows (`/company/projects/:id/workflows`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | Alba: `WorkflowResource` (scope_indicator, steps_count, last_run) | ✅ |
| b | `Projects::WorkflowsController` — index + create + update + destroy (soft_delete) | ✅ |
| c | Routes: workflows `only: %i[index create update destroy]` | ✅ |
| d | UI: Mantine `SimpleGrid` cards + search + CRUD modals + Run History link | ✅ |

### 3.8 — Tab: Sessions (`/company/projects/:id/sessions`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | Alba: `TerminalSessionResource` | ✅ |
| b | `Projects::SessionsController` — index with sessions (includes user, output_assets) | ✅ |
| c | UI: Mantine `Table` + filters (Agent, Status) + badges + tokens + cost + duration + New Session btn | ✅ |

### 3.8b — Tab: Workflow Runs (`/company/projects/:id/workflow_runs`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | Alba: `WorkflowRunResource` (workflow_name, steps_completed/total) | ✅ |
| b | `Projects::WorkflowRunsController` — index with runs (includes workflow, step_runs) | ✅ |
| c | UI: Mantine `Table` + status filter + steps progress + duration + open link | ✅ |

### 3.9 — Tab: Analytics (`/company/projects/:id/analytics`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| a | Client-side fetch to existing API endpoints (5 endpoints) | ✅ |
| b | UI: Recharts (AreaChart, PieChart, BarChart) + stat cards + scope/period filters | ✅ |

### 3.10 — Simple project tabs (config_items, agents, tools, skills, mcp_servers, repositories, integrations, members/collaborators)

> Shared components in `shared/resources/` with the `basePath` pattern. Unified stack: `@mantine/form` + `zodResolver` + `router.post/patch/delete`.

| # | Task | Status |
|---|--------|--------|
| a | Shared: Skills (Content + FormModal + DeleteModal) | ✅ |
| b | Shared: Agents (Content + FormModal + DeleteModal) | ✅ |
| c | Shared: Tools (Content + FormModal + DeleteModal + ToolFileEditor) | ✅ |
| d | Shared: MCP Servers (Content + FormModal + DeleteModal + ConfigItemValueField) | ✅ |
| e | Shared: ConfigItems (Content + FormModal) — mantine/form + zodResolver | ✅ |
| f | Shared: Repositories (Content + EditModal with Autocomplete branches) | ✅ |
| g | Shared: Integrations (Content — router.delete only, no form) | ✅ |
| h | Project Members → Collaborators (select from company users, not invite) | ✅ |
| i | Backend: project controllers with CRUD + visible_for_project | ✅ |
| j | Unified pattern for all forms: @mantine/form + zodResolver + router | ✅ |
| k | UX fix: Autocomplete → Select (searchable) for branches and models (full list on open) | ✅ |

### 3.11 — Workflows List (`/company/workflows`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 3.11.1 | Alba: `WorkflowResource` (already existed) | ✅ |
| 3.11.2 | `Web::Company::WorkflowsController` + CRUD | ✅ |
| 3.11.3 | Route: `resources :workflows` in web company scope | ✅ |
| 3.11.4 | UI: `Company/Workflows/Index.tsx` — Card grid + search + CRUD modals | ✅ |
| 3.11.5 | Remove company-level `workflowsApi` | ⬜ (during cleanup) |

**Additional Alba resources (Phase 3):**
- `TerminalSessionResource` — user_name, user_email, project_name, pending_artifacts_count
- `WorkflowResource` — scope_indicator, steps_count, last_run_at/status, has_active_runs, description_excerpt
- `WorkflowRunResource` — workflow_name, steps_completed, steps_total
- `BoardResource`, `BoardColumnResource`, `BoardTaskResource` — assignee_name, comments_count, children_count

**Criterion:** ✅ Project page with tabs on Inertia. Board with drag-and-drop. Analytics with Recharts. All project tabs functional.

---

## Phase 4: Realtime-heavy pages — ✅ COMPLETED

> Goal: Sessions (xterm.js + ActionCable), Workflow Run (live progress), Artifacts.

### 4.1 — Sessions List (`/company/sessions`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.1.1 | Alba: `TerminalSessionResource` (already existed) | ✅ |
| 4.1.2 | `Web::Company::SessionsController#index` | ✅ |
| 4.1.3 | Route: `resources :sessions, only: :index` in company scope | ✅ |
| 4.1.4 | UI: `Company/Sessions/Index.tsx` — Table + Agent/Status filters + Project column | ✅ |
| 4.1.5 | 15s polling when active sessions + `router.reload` | ✅ |

### 4.2 — Session New (`/company/sessions/new`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.2.1 | `Web::Company::Sessions::NewController` | ✅ |
| 4.2.2 | Route: `resource :new` in sessions collection | ✅ |
| 4.2.3 | UI: Project select, Agent SegmentedControl, Mode, Prompt, BMAD switch | ✅ |
| 4.2.4 | API POST `/api/v1/terminal_sessions` → redirect to session view | ✅ |

### 4.3 — Session View (`/company/sessions/:id`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.3.1 | `Web::Company::SessionsController#show` + ttyd/IDE URLs | ✅ |
| 4.3.2 | Route: `resources :sessions, only: %i[index show]` | ✅ |
| 4.3.3 | UI: Header (agent, state, finish, new) + iframe terminal/editor | ✅ |
| 4.3.4 | UI: Ended state summary (duration, tokens, cost, models, artifacts) | ✅ |
| 4.3.5 | UI: Waiting state with refresh | ✅ |
| 4.3.6 | ActionCable `TerminalSessionChannel` → `router.reload` for live status | ✅ |
| 4.3.7 | Session Artifacts review page | ✅ |

### 4.4 — Project Sessions (nested in project) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.4.1 | `Projects::SessionsController` — new + show (reuses TerminalSessionResource) | ✅ |
| 4.4.2 | Route: `resources :sessions, only: %i[index new show]` in project scope | ✅ |
| 4.4.3 | UI: `Projects/Sessions/NewPage.tsx` — project-scoped (no project Select, agent + mode + BMAD) | ✅ |
| 4.4.4 | UI: `Projects/Sessions/ShowPage.tsx` — ProjectLayout + iframe terminal/editor + summary | ✅ |
| 4.4.5 | UI: `SessionsPage.tsx` — links to project-scoped show instead of company + 15s polling | ✅ |

### 4.5 — Workflow Run (`/company/projects/:id/workflow_runs/:id`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.5.1 | `WorkflowRunsController#show` + nested step_runs/sub_step_runs + assets | ✅ |
| 4.5.2 | Route: `resources :workflow_runs, only: %i[index show]` | ✅ |
| 4.5.3 | UI: Step timeline with detail panel, statuses, sub-steps, errors, session links | ✅ |
| 4.5.4 | UI: Cancel button, duration, progress, cost | ✅ |
| 4.5.5 | ActionCable `WorkflowRunChannel` → `router.reload` for live progress | ✅ |
| 4.5.6 | Workflow Assets tab: grouped by step, download, promote to project | ✅ |
| 4.5.7 | Approve/Skip/Retry step actions + Finish agent session | ✅ |

### 4.6 — Session Artifacts (`/company/sessions/:id/artifacts`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.6.1 | Alba: `SessionArtifactResource` (name, folder, status, file_size, content_type, download_url) | ✅ |
| 4.6.2 | `Web::Company::Sessions::ArtifactsController` — index + review (save/dismiss decisions) | ✅ |
| 4.6.3 | Route: `resources :artifacts` nested in sessions with `post :review` | ✅ |
| 4.6.4 | UI: `Company/Sessions/Artifacts.tsx` — Table + checkboxes + Save selected / Dismiss all | ✅ |
| 4.6.5 | UI: `Show.tsx` — Review Artifacts button + clickable pending badge | ✅ |

### 4.7 — Board ActionCable + Assets tab — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.7.1 | `BoardChannel` subscription → `router.reload` for live board updates | ✅ |
| 4.7.2 | Task sidebar: Assets tab (useTaskAssets hook + list) | ✅ |

### 4.8 — Onboarding Terminal Auth — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.8.1 | Step 3: Agent list panel + auth terminal iframe (left/right split) | ✅ |
| 4.8.2 | ActionCable `TerminalSessionChannel` for live auth status | ✅ |
| 4.8.3 | Credential save polling after auth complete | ✅ |

### 4.9 — Assets Upload via Uppy — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 4.9.1 | Shared `AssetsContent` upload modal with Uppy + AwsS3 presign | ✅ |
| 4.9.2 | Progress bar, drag & drop, folder selection | ✅ |
| 4.9.3 | Project assets page: Upload button | ✅ |

**Additional Alba resources (Phase 4):**
- `SessionArtifactResource` — file_size, content_type, download_url (via latest_version)
- `StepResource` — full step details with sub_steps, tool_ids, skill_ids, mcp_server_ids
- `SubStepResource` — name, description, instructions, position, required

**Criterion:** ✅ all realtime pages on Inertia. ActionCable hooks → `router.reload`/`router.replace`.

---

## Phase 5: Builders — ✅ COMPLETED

> Goal: Workflow Builder and Aixle Builder — the most interactive pages.

### 5.1 — Workflow Builder (`/company/projects/:id/workflows/:id/builder`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 5.1.1 | Alba: `StepResource`, `SubStepResource` | ✅ |
| 5.1.2 | Step sidebar with reorder (up/down arrows) + step chips (deps, auto-run, BMAD, root) | ✅ |
| 5.1.3 | Step detail panel: name, description, instructions, agent, runtime, model | ✅ |
| 5.1.4 | Debounced autosave (500ms) via `useDebouncedCallback` + API calls | ✅ |
| 5.1.5 | UI: Mantine `Accordion` (base resources + sub-steps) + `Paper` + `Modal` (delete) | ✅ |
| 5.1.6 | Sub-steps: CRUD, name/description/instructions/required, reorder | ✅ |
| 5.1.7 | Base Resources: tools, skills, MCP servers, assets multi-select + inherit toggle | ✅ |
| 5.1.8 | Step config: auto-run, skip policy, on failure, max retries, tools, MCP, skills, mount repos, BMAD, dependencies | ✅ |
| 5.1.9 | Read-only mode for company-level workflows | ✅ |
| 5.1.10 | `Web::Company::Projects::WorkflowsController#builder` + route | ✅ |
| 5.1.11 | Remove `stepsApi` | ⬜ (during cleanup) |

### 5.2 — Aixle Builder (`/company/projects/:id/aixle_builder`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 5.2.1 | Landing page: hero, agent runtime select, project assets multi-select | ✅ |
| 5.2.2 | Start builder → API POST + redirect to session page | ✅ |
| 5.2.3 | Previous sessions table with status badges | ✅ |
| 5.2.4 | `Web::Company::Projects::AixleBuilderController` — show + session | ✅ |
| 5.2.5 | Routes: `resource :aixle_builder` in project scope | ✅ |
| 5.2.6 | Remove `aixleBuilderApi` | ⬜ (during cleanup) |

### 5.3 — Aixle Builder Session (`/company/projects/:id/aixle_builder/:id/session`) — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| 5.3.1 | Split layout: terminal/IDE (left) + tabs (right) | ✅ |
| 5.3.2 | Activity tab: meta-activity log with entity names + actions | ✅ |
| 5.3.3 | Workflows tab: polling preview list with step counts | ✅ |
| 5.3.4 | Board tab: columns preview with workflow bindings | ✅ |
| 5.3.5 | ActionCable `TerminalSessionChannel` → live session updates | ✅ |
| 5.3.6 | Finish session button + Live badge | ✅ |

**Criterion:** ✅ all pages on Inertia + Mantine. Builders are fully functional.

---

## Refinements — ✅ COMPLETED

> Minor functional refinements identified while reconciling against the legacy specification.

### D.1 — Run Workflow Modal — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| D.1.1 | `RunWorkflowModal` shared component (execution mode, wave viz, custom per-step, agent, repos, assets) | ✅ |
| D.1.2 | Integration into `BuilderPage` — Run button → modal | ✅ |
| D.1.3 | Integration into `WorkflowsPage` — Run button → modal (instead of redirect) | ✅ |
| D.1.4 | Controller: pass `steps`, `assets`, `repositories`, `configured_agents` into WorkflowsPage props | ✅ |
| D.1.5 | Controller: pass `repositories` into BuilderPage props | ✅ |

### D.2 — Board Task Sidebar: Statistics tab — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| D.2.1 | `useTaskStatistics` hook (lazy fetch on tab activation) | ✅ |
| D.2.2 | UI: 3 stat cards (cost, tokens, run time) + workflow breakdown + waits | ✅ |
| D.2.3 | Skeleton loading state | ✅ |

### D.3 — Company-level Workflow Builder — ✅ COMPLETED

| # | Task | Status |
|---|--------|--------|
| D.3.1 | Route: `get :builder` in company workflows scope | ✅ |
| D.3.2 | `Web::Company::WorkflowsController#builder` action | ✅ |
| D.3.3 | `Company/Workflows/BuilderPage.tsx` — full editor (steps, sub-steps, autosave) | ✅ |
| D.3.4 | Company Workflows Index: Configure button → builder | ✅ |

---

## Phase 6: Cleanup — ⬜ NOT STARTED

> Goal: remove legacy. One stack, one entrypoint.

### 6.1 — Removing the old SPA

| # | Task | Status |
|---|--------|--------|
| 6.1.1 | Remove `entrypoints/application.tsx` | ⬜ |
| 6.1.2 | Remove `app/frontend/app/` (App.tsx, routeTree.tsx, providers/) | ⬜ |
| 6.1.3 | Remove `app/frontend/pages/` (old pages) | ⬜ |
| 6.1.4 | Move `pages-inertia/` → `pages/` | ⬜ |
| 6.1.5 | Remove `app/views/layouts/web/application.html.haml` | ⬜ |

### 6.2 — Removing npm dependencies

| # | Package | Replacement | Status |
|---|-------|--------|--------|
| 6.2.1 | `@tanstack/react-router` + devtools | Inertia server-side routing | ⬜ |
| 6.2.2 | `@reduxjs/toolkit` + `react-redux` | Inertia props + `inertia_share` | ⬜ |
| 6.2.3 | `@mui/material` + `@mui/icons-material` + `@mui/lab` | Mantine | ⬜ |
| 6.2.4 | `@emotion/react` + `@emotion/styled` | CSS Modules (Mantine) | ⬜ |
| 6.2.5 | `axios` | Inertia v3 built-in HTTP + `useHttp` | ⬜ |
| 6.2.6 | `notistack` | `@mantine/notifications` | ⬜ |
| 6.2.7 | `react-hook-form` + `@hookform/resolvers` | `@mantine/form` | ⬜ |
| 6.2.8 | `mui-sx`, `classnames` | Mantine className + Tailwind | ⬜ |
| 6.2.9 | `qs`, `camelcase-keys`, `decamelize-keys` | Alba/Typelizer format | ⬜ |

### 6.3 — Removing backend legacy

| # | Task | Status |
|---|--------|--------|
| 6.3.1 | `bundle remove active_model_serializers` (→ Alba) | ⬜ |
| 6.3.2 | `bundle remove gon` (→ Inertia shared data) | ⬜ |
| 6.3.3 | Remove all `app/serializers/` (→ `app/resources/`) | ⬜ |
| 6.3.4 | Review API controllers: what to keep for mobile/integrations | ⬜ |
| 6.3.5 | Remove catch-all `get "*path" => "home#show"` | ⬜ |

### 6.4 — Shared-code review

| # | Task | Status |
|---|--------|--------|
| 6.4.1 | Remove `shared/api/` (baseApi, store, convertCase, QueryTag) | ⬜ |
| 6.4.2 | Review `shared/lib/` — keep ActionCable consumer, remove the rest | ⬜ |
| 6.4.3 | Remove the MUI theme (`shared/theme/baseTheme/`, 30 files) | ⬜ |

### 6.5 — SSR (optional)

| # | Task | Status |
|---|--------|--------|
| 6.5.1 | `config.ssr_enabled = ViteRuby.config.ssr_build_enabled` | ⬜ |
| 6.5.2 | Create `ssr.ts` entrypoint | ⬜ |

**Criterion:** one entrypoint, no MUI/Redux/Router, types from Typelizer, bundle ~150-200KB.

---

## Serializer migration (AMS → Alba)

| Phase | AMS → Alba |
|------|-----------|
| 0 | `current_user_serializer` → `CurrentUserResource` ✅, `company_serializer` → `CompanyResource` ✅ |
| 1 | `user_serializer`, `config_item_serializer`, `integration_serializer`, `repository_serializer` |
| 2 | `agent_serializer`, `agent_credential_serializer`, `tool_serializer`, `tool_file_serializer`, `skill_serializer`, `mcp_server_serializer`, `asset_*_serializer` (3) |
| 3 | `project_serializer`, `board_*_serializer` (5), `workflow_serializer`, `workflow_cost_analytics_serializer`, `column_*_serializer` (2), `task_*_serializer` (4) |
| 4 | `terminal_session_serializer`, `session_log_serializer`, `session_artifact_serializer`, `workflow_run_*_serializer` (2), `step_run_serializer`, `sub_step_run_serializer` |
| 5 | `step_serializer`, `sub_step_serializer`, `tool_result_serializer` |

---

## ActionCable: hook migration

| Hook | Strategy |
|-----|-----------|
| `useWorkflowRunChannel` | `router.reload({ only: ['run'] })` + `router.replace` for live progress |
| `useBoardChannel` | `router.reload({ only: ['board'] })` |
| `useMetaActivityChannel` | `router.replace(...)` for AI streaming |
| `useTerminalSession` | **No changes** — raw ActionCable + xterm.js |
| `useAiEngineEvents` | `router.replace(...)` for AI events |
| `useTtydWebSocket` | **No changes** — raw WebSocket |

---

## Estimate

| Phase | Pages | SP | Duration (1 dev) |
|-------|---------|-----|---------------------|
| 0: Infrastructure | 0 | 13 | 1 week ✅ |
| 1: Simple CRUD | 5 | 21 | 2 weeks |
| 2: CRUD + forms | 7 | 34 | 2-3 weeks |
| 3: Complex + live | 6+ | 55 | 3-4 weeks |
| 4: Realtime | 5 | 55 | 3-4 weeks |
| 5: Builders | 3 | 55 | 3-4 weeks |
| 6: Cleanup | — | 21 | 1-2 weeks |
| **Total** | **~26** | **~254** | **~15-20 weeks** |

---

## What does NOT change

`@xterm/xterm`, `@uiw/react-codemirror`, `@dnd-kit/*`, `@uppy/*`, `@rails/actioncable`, `recharts`, `react-markdown`, `mermaid`, `zod`, `ts_routes`, `tailwindcss`, `dayjs`
