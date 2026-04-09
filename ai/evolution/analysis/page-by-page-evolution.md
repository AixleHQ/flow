# Aixle — Page-by-Page Evolution Checklist

> **Purpose:** Comparison of the MUI legacy and Inertia implementations page by page. For each page: what it was, what it is, what is missing, and suggestions for improvement.
>
> **Sources:**
> - `ai/epics/legacy-spa-detailed-spec.md` — pixel-level MUI specification
> - `ai/epics/legacy-spa-functionality-audit.md` — high-level MUI overview
> - `ai/epics/frontend-rewrite-tracking.md` — Inertia migration tracking
> - Code in `app/frontend/pages-inertia/`, `shared/resources/`, `shared/ui-inertia/`, `layouts/`
>
> **Legend:**
> - ⬜ Not yet reviewed — awaiting analysis and improvements
> - 🔵 In progress
> - ✅ Review completed — feature parity + UX improvements applied
>
> **Created:** 2026-04-03

---

## Table of Contents

1. [Application Shell](#1-application-shell)
2. [Login](#2-login)
3. [Onboarding](#3-onboarding)
4. [Projects List](#4-projects-list)
5. [Project Overview Dashboard](#5-project-overview-dashboard)
6. [Board (Kanban)](#6-board-kanban)
7. [Workflows (list)](#7-workflows-list)
8. [Workflow Builder](#8-workflow-builder)
9. [Workflow Runs (list)](#9-workflow-runs-list)
10. [Workflow Run (show)](#10-workflow-run-show)
11. [Run Workflow Modal](#11-run-workflow-modal)
12. [Aixle Builder](#12-aixle-builder)
13. [Sessions (list)](#13-sessions-list)
14. [Session New](#14-session-new)
15. [Session View (show)](#15-session-view-show)
16. [Session Artifacts](#16-session-artifacts)
17. [Analytics](#17-analytics)
18. [Agents](#18-agents)
19. [Tools](#19-tools)
20. [Skills](#20-skills)
21. [MCP Servers](#21-mcp-servers)
22. [Config Items](#22-config-items)
23. [Integrations](#23-integrations)
24. [Repositories](#24-repositories)
25. [Assets](#25-assets)
26. [Company Members](#26-company-members)
27. [User Profile](#27-user-profile)
28. [Project Settings](#28-project-settings)
29. [Project Members](#29-project-members)

---

## 1. Application Shell ✅

### MUI Legacy
- **AppHeader**: Company logo → Project selector (persisted in localStorage) → 3 dropdown menus (Work, Agent Context, Settings) → User avatar menu
- **AppSidebar**: 220px ↔ 56px collapsible (persisted in localStorage), 3 groups (Primary, Config, Admin), icon-only mode when collapsed, toggle button at bottom
- **Route pending indicator**: LinearProgress bar at top during transitions
- **Footer**: "Powered by" + Logo

### Inertia Current
- **AppHeader** (317 LOC): Project selector ✅, 3 dropdown menus ✅, User menu ✅, Company logo ✅
- **AppSidebar**: Collapse 220↔56 ✅, icon-only + tooltips ✅, toggle button ✅, mobile drawer ✅
- **Route indicator**: InertiaRouteIndicator ✅ (Progress bar on router start/finish)
- **Footer**: "Powered by" + Logo ✅

### Missing Features
- [x] Sidebar collapse (220px ↔ 56px) with localStorage persist
- [x] Icon-only mode when collapsed (with tooltips)
- [x] Toggle button at bottom of sidebar
- [x] Route pending indicator (Inertia `router.on('start'/'finish')` → NProgress or custom)

### UX Improvements
- [x] Add breadcrumbs to the header (context: Company → Project → Tab) — `Breadcrumbs` component in AppHeader
- [x] Animation when toggling the sidebar (smooth transition) — `transition: width 0.2s ease`
- [x] Active indicator in the dropdown menu — highlight the current page more clearly — `menuItemActive` + `navButtonStyles(isActive)`
- [x] Mobile responsive: sidebar as a drawer on mobile

---

## 2. Login ✅

### MUI Legacy
- Centered card 420px, Logo, Google OAuth button (4-color SVG), "OR" divider, email + password fields, "Sign in" button, footer "AI Agent Orchestration Platform"
- Auto-redirect if authenticated
- OAuth error handling via URL params (pending_approval, deactivated, oauth_failed, oauth_error)
- Zod validation (email + password required)

### Inertia Current
- Centered card ✅, Logo ✅, Google OAuth (prominent, full-width, size="lg") ✅, email/password ✅, error handling ✅
- Zod validation ✅, PasswordInput with visibility toggle ✅, fadeSlideUp animation ✅
- Radial gradient background (via PageShell) ✅
- Auto-redirect: server-side in SessionsController ✅

### Missing Features
- [x] Auto-redirect if already authenticated (server-side in `Web::SessionsController#new`)
- [x] Zod validation on client (`loginSchema` with `safeParse`)

### UX Improvements
- [x] Add visual branding: gradient background or subtle pattern — radial gradient via PageShell
- [x] Form appearance animation (fade in / slide up) — `@keyframes fadeSlideUp`
- [x] Remember me checkbox — Mantine `Checkbox` added to login form
- [x] Password visibility toggle — Mantine `PasswordInput` with `visibilityToggle`
- [x] More prominent Google OAuth button (primary action vs secondary form) — full-width `size="lg"` first element

---

## 3. Onboarding ✅

### MUI Legacy (4-step wizard)
- Step 1: Profile (Position select, Language select, auto-save 300ms debounce)
- Step 2: Select Agents (2×2 grid cards with checkboxes, color bars, auto-save)
- Step 3: **Authenticate** (agent list sidebar + xterm.js terminal, auth polling 500ms × 20 attempts)
- Step 4: Complete (summary cards, "Get Started" button)
- LinearProgress + numbered circles, welcome section with company branding

### Inertia Current (299 LOC)
- 4-step Stepper ✅
- Step 1: Profile form ✅
- Step 2: Agent selection cards ✅
- Step 3: **Placeholder** — shows status but no terminal auth ❌
- Step 4: Summary + Get Started ✅

### Missing Features
- [x] Step 3: xterm.js terminal integration (AgentAuthTerminal) — ttyd iframe
- [x] Step 3: Auth polling (every 3s + ActionCable + post-finish 500ms polling ~20 attempts)
- [x] Step 3: Left panel agent list with status indicators — authenticated/click-to-auth badges
- [x] Step 3: "Save Authentication" button (disabled until auth detected)
- [x] Auto-save with debounce on field changes — 300ms debounce
- [x] Welcome section with company logo and branding — welcomeCard with logo + gradient
- [x] Progress bar (LinearProgress) in addition to Stepper — `Progress` bar above Stepper
- [x] Validation warnings ("⚠️ Please fill in all required fields")

### UX Improvements
- [x] Agent cards: brighter color bars, hover effects — translateY(-2px) + box-shadow on hover
- [ ] Step indicators: animation when transitioning between steps
- [x] Confetti or celebration animation on Step 4 completion — CSS confetti with falling colored dots

---

## 4. Projects List ✅

### MUI Legacy
- Title + "Create Project" button, Search field
- 3-column responsive grid of ProjectCards
- ProjectCard: name (18px bold), description (2-line clamp, 52px min-height), collaborator chip, footer with stats + last activity
- Hover: blue border, translateY(-2px), shadow
- Empty states (no projects, no search results)

### Inertia Current
- Title + Create button ✅, Search ✅
- 3-column SimpleGrid ✅, ProjectCard ✅ with stats (sessions, workflows, board tasks, members)
- Hover: translateY(-2px) + shadow ✅, Last activity ✅, Sort options ✅
- Empty states ✅, Create modal ✅

### Missing Features
- [x] Collaborator chip on card (N collaborators) — Badge with member count
- [x] Last activity relative timestamp on card footer — `formatRelativeTime`
- [x] Hover: translateY(-2px) + shadow — in CSS Module

### UX Improvements
- [x] Card stats preview (sessions count, spend, active workflows) — sessions, workflows, board tasks, members shown
- [x] Project status indicator (active/archived) — colored dot next to project name
- [ ] Card thumbnail/icon for visual variety
- [x] Sort options (by name, last activity, creation date) — Select with SORT_OPTIONS
- [x] Quick actions on card hover (Open, Settings, Delete) — ActionIcon overlay on hover

---

## 5. Project Overview Dashboard ✅

### MUI Legacy
- 60-second auto-refresh polling
- 4 stat cards: Sessions (PlayCircleIcon blue), Spend (AttachMoneyIcon green), Workflows (info), Board Tasks (warning orange)
- Two-column: Recent Activity (color-coded dots, 13 event types) + Workflow Runs (4 progress bars)
- Board Task Distribution grid

### Inertia Current
- 4 stat cards ✅ with ThemeIcon backgrounds + colored left border accent
- Recent Activity ✅ (color-coded dots)
- Workflow Runs progress bars ✅
- Board Task Distribution with Progress bars ✅
- 60s auto-refresh polling ✅, Responsive mobile ✅

### Missing Features
- [x] Auto-refresh polling (60s interval) — `setInterval` + `router.reload`
- [x] Stat card icons with a background circle/card — ThemeIcon variant="light"

### UX Improvements
- [x] Stat cards: gradient or colored accent, hover animation — colored `borderLeft` accent
- [x] Activity feed: timeline layout instead of a plain list (vertical line + dots) — vertical line with colored dots
- [x] Activity: "View all" link / pagination — "View all activity" anchor
- [x] Workflow Runs: clickable bars → navigate to filtered runs list — `router.visit` with status filter
- [ ] Sparkline mini-charts on stat cards (7-day trend)
- [x] Board distribution: progress bars instead of a numbers-only grid
- [x] Responsive: stack cards on mobile — `SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}`

---

## 6. Board (Kanban) ✅ (S-09 2026-04-04)

### MUI Legacy — THE MOST COMPLEX PAGE
- Horizontal scrollable kanban, DnD Kit drag-and-drop
- **Columns**: expanded (280px) / collapsed (44px), column header (name + count + add), drop highlight
- **Collapsed columns**: badge count, vertical name, up to 10 task indicators (colored bars with pulse animation)
- **Task cards**: priority dot, title, workflow dots (pulse), type chip, tags (max 3 + overflow), assignee avatar, comments count
- **Filter bar**: Assignee, Type, Priority, Tags, Search, Presets (save/load)
- **Task Sidebar** (480px, expandable to 50vw): 5 tabs:
  - Details: inline editable title/description, type/priority/assignee selects, tags, parent epic, workflow runs, child tasks, pending waits
  - Comments: markdown, tag filtering, author type filter, collapse/expand
  - Assets: upload, list, delete
  - Activity: paginated (15/page)
  - Statistics: cost/tokens/time cards, BarChart breakdown by workflow, waits section
- **Board Settings**: reorder columns (DnD), workflow bindings, trigger modes (auto/manual), add/remove columns
- **Activity Feed Panel**: bottom collapsible, 20/page, paginated
- **Create Task dialog**: title, description, type, priority, column, assignee, parent epic, tags
- **WebSocket**: BoardChannel → deferred refetch during drag
- Optimistic updates on task move

### Inertia Current (1534 LOC)
- Kanban layout ✅, DnD Kit ✅, Task cards with priority/tags/workflow dots/comments ✅
- Task Sidebar with 5 tabs ✅, Filter Bar ✅, Board Settings ✅, Column collapse ✅
- Activity Feed Panel ✅, ActionCable ✅, Optimistic updates ✅, URL params ✅
- Create Task modal ✅, Board creation from preset ✅, Inline editing ✅, Statistics tab ✅

### Missing Features
- [x] **Task Sidebar** — 5 tabs: Details, Comments, Assets, Activity, Statistics
- [x] **Filter Bar** — Assignee, Type, Priority, Search (Tags filter missing)
- [x] **Filter Bar** — Tags filter (MultiSelect from all task tags) ✅
- [ ] **View Presets** — save/load filter presets
- [x] **Board Settings dialog** — workflow bindings, trigger modes, add/remove columns, drag reorder ✅
- [x] **Board Settings** — interactive column reorder via @dnd-kit SortableContext ✅
- [x] **Column collapse** — collapsed view with badge count
- [x] **Activity Feed Panel** — bottom collapsible panel with pagination
- [x] **Collapsed task indicators** — colored priority bars with pulse animation for active workflows
- [x] **Workflow dots** on task cards (active/pending workflow status with pulse)
- [x] **Comments count** badge on task cards
- [x] **Tags** on task cards (max 3 + overflow chip)
- [x] **Priority dot** on task cards
- [x] **Inline editing** in task sidebar (title + select fields)
- [x] **"Run workflow" button** in task sidebar (when manual trigger mode) ✅
- [x] **ActionCable** live updates → BoardChannel subscription
- [x] **Optimistic updates** on task move (revert on error)
- [x] **URL params** persistence (task deep-link via `?task=`)
- [x] **Board Statistics tab** per task — cost/tokens/time/workflow breakdown

### UX Improvements
- [x] Smooth drag animation (spring physics + drop easing + rotation overlay) ✅
- [ ] Task card: mini avatar stack for multiple assignees
- [ ] Column WIP limits visual indicator
- [x] Keyboard shortcuts (N=new task, /=search, Escape=close sidebar) — `useEffect` keydown handler
- [ ] Task card preview on hover (without opening sidebar)

---

## 7. Workflows (list) ✅

### MUI Legacy
- Title + "Run History" button + "New Workflow" button
- **AixleBuilderBanner** — gradient purple card with "Open Builder" button (project context only)
- Search (debounced 300ms)
- 3-column grid of workflow cards: name + "company" chip, description, meta (steps count + last run), action buttons (Run/Copy/Configure/Edit/Delete)
- Different buttons for own vs inherited (company) workflows

### Inertia Current
- **Company**: Card grid + search + CRUD modals ✅
- **Project**: Card grid + search + CRUD modals ✅, Run button ✅, "company" chip ✅, steps count + last run ✅, Run History button ✅

### Missing Features
- [x] "Run" button on workflow card (project context) — opens RunWorkflowModal
- [x] "Copy & Configure" for inherited company workflows — IconCopy button creates project copy
- [x] "company" chip on inherited workflows — Badge "company" when `isInherited`
- [x] Steps count + last run meta on cards — `steps_count` + "Last run {date}"
- [ ] AixleBuilderBanner (gradient card with Open Builder)
- [x] "Run History" button → navigate to workflow runs — IconHistory button
- [x] Debounced search — `useDebouncedValue` 300ms

### UX Improvements
- [x] Workflow card: visual status indicator (has active runs, last run status) — colored dot with pulse for running
- [ ] Quick run from card (without opening modal)
- [ ] Card actions as icon buttons on hover (cleaner look)

---

## 8. Workflow Builder ⬜ — NOT IMPLEMENTED (Phase 5)

### MUI Legacy — SECOND MOST COMPLEX PAGE
- Split layout: Step Sidebar (left) + Detail Panel (right)
- Editable workflow name + description in header
- **Step Sidebar**: ordered list, position chips (Requires/Auto-run/BMAD/Root/Dependencies), reorder arrows
- **Detail Panel**: 22 fields/sections (name, description, instructions, agent, runtime, model, auto-run, skip policy, on failure, retries, tools, MCP servers, skills, repos, BMAD, dependencies, sub-steps, input/output asset specs)
- **Base Resources Accordion**: inherit all project resources toggle, 4 multi-selects
- **Auto-save**: 500ms debounce with guarded draft sync
- **Read-only mode** for company workflows in project context
- Sub-steps: add/edit/delete/reorder

### Inertia Current
- **Not implemented** ❌

### Full Implementation Needed
- [ ] The entire workflow builder (Phase 5 in frontend-rewrite-tracking.md)

---

## 9. Workflow Runs (list) ✅

### MUI Legacy
- State filter Select (All, Running, Completed, Failed, Cancelled, Pending)
- 10s polling
- Columns: Status (icon chip), Workflow (name + #id), Mode, Steps (completed/total), Duration, Started (relative), Action (OpenInNew)

### Inertia Current
- **Company**: no dedicated page ❌
- **Project**: Table + status filter ✅, steps progress ✅, duration ✅, 10s polling ✅, Mode column ✅, OpenInNew ✅

### Missing Features
- [ ] Company-level workflow runs page
- [x] 10s polling for live status updates — `setInterval` when `hasActive`
- [x] Mode column (Interactive/Auto-run/Custom) — `MODE_LABELS`
- [x] OpenInNew action for running/paused runs — `IconExternalLink` target="_blank"

### UX Improvements
- [x] Live status badges with pulse animation for running — CSS `@keyframes wfRunPulse`
- [ ] Auto-scroll to newest when new run appears

---

## 10. Workflow Run (show) 🔵

### MUI Legacy
- **Header**: breadcrumbs, workflow name, state badge, live duration (JetBrains Mono), step counter, "Cancel Workflow" button
- **DAG Timeline**: horizontal scrollable, steps grouped by waves, status indicators (colored circles with ✓/●/✋/✗/→), wave connectors, past failures badge, click to select
- **Terminal Panel**: dark bg, xterm.js via TerminalSessionWidget (resizable split editor+terminal)
- **Right Panel** (260px): Sub-steps list with status, Step Note, "Finish Agent Session" button, Action buttons (Approve/Skip/Retry), Failed step error
- **Tabs**: Steps + Workflow Assets (disabled when active)
- **StatusBar** (bottom 28px): agent, status, user, duration, cost
- Auto-follow: auto-select running/waiting step
- ActionCable → live progress

### Inertia Current (766 LOC)
- Vertical timeline with step cards ✅, Sub-steps panel ✅, Action buttons ✅
- Breadcrumbs ✅, StatusBar ✅, ActionCable ✅, Auto-follow ✅
- Approve/Skip/Retry ✅, Finish Agent Session ✅, Skip dialog ✅, Assets tab ✅

### Missing Features
- [ ] **DAG Timeline** with wave grouping (horizontal scroll, wave connectors) — currently vertical linear
- [ ] **Terminal Panel** — xterm.js / iframe for step session (link to session only)
- [x] **Right Panel** — sub-steps list, step note, action buttons
- [x] **Approve / Skip / Retry** action buttons for waiting_input steps
- [x] **"Finish Agent Session"** button for running steps
- [x] **Skip dialog** (reason text field)
- [x] **Workflow Assets tab** (grouped by step, disabled when active)
- [x] **StatusBar** (bottom) — agent, status, user, duration, cost
- [x] **Past failures badge** on step indicators — red badge with failure count
- [x] **Auto-follow** — auto-select running/waiting step
- [x] **ActionCable** live progress updates — WorkflowRunChannel
- [x] **Breadcrumbs** (Projects → Project → Runs → Run)

### UX Improvements
- [x] Step cards: more visual status (icons + colors + pulse) — pulse animation on running
- [ ] Terminal/details: resizable split panel
- [x] Duration: live counter for running steps — `LiveDuration` component with 1s interval
- [ ] Promote artifacts: batch mode

---

## 11. Run Workflow Modal ✅

### MUI Legacy
- Title "Run: {workflowName}"
- **Execution Mode**: 3 options (Interactive, Fully automatic, Custom) — per-step toggle in Custom mode
- **Wave visualization**: step chips grouped by wave, arrows between waves
- **Agent Runtime**: Select of configured agents
- **Repositories**: Autocomplete multiple
- **Input Assets**: Autocomplete multiple, grouped by folder
- Buttons: Cancel + "Run Workflow"

### Inertia Current
- RunWorkflowModal with SegmentedControl (Interactive/Automatic/Custom) ✅
- Custom mode per-step Switch toggles ✅, Agent runtime selector ✅
- Repository + Asset MultiSelects ✅, Wave-based step visualization ✅

### Missing Features (now done)
- [x] Run Workflow Modal with execution mode selector — SegmentedControl
- [x] Wave DAG visualization (interactive/automatic)
- [x] Custom mode: per-step auto/interactive toggle — Switch components
- [x] Agent runtime selector
- [x] Repository + asset selectors

---

## 12. Aixle Builder ⬜ — NOT IMPLEMENTED (Phase 5)

### MUI Legacy
- **Landing page**: hero section, agent runtime select, model select, project assets, start button, previous sessions table
- **Session view**: split layout (terminal left, 3 tabs right: Activity, Workflows, Board)
- **Activity tab**: entity icon, 21 action types, newest-first
- **WebSocket**: MetaActivityChannel

### Inertia Current
- **Not implemented** ❌

### Full Implementation Needed
- [ ] The entire Aixle Builder (Phase 5)

---

## 13. Sessions (list) 🔵

### MUI Legacy
- **Filters**: Agent type Select + State Select
- **20 per page, 15s polling**
- **Columns**: ID, Agent (colored chip), Type, Status + pending artifacts badge, User, Project, Tokens (tooltip breakdown), Cost (monospace), Models (outlined chips), Duration, Started (relative + tooltip), OpenInNew
- **Pagination** at bottom

### Inertia Current
- Filters: Agent + Status ✅
- Table with all columns ✅, Token breakdown tooltip ✅, Pending artifacts badge ✅, Models chips ✅
- 15s polling ✅

### Missing Features
- [ ] **Pagination** (server-side, 20 per page) — currently loads all
- [x] **15s polling** for live status updates — `setInterval` 15s when active sessions
- [ ] **"New Session" button** → navigate (company page has it ✅, project verify)
- [x] OpenInNew only for `ready` sessions (company has it ✅)

### UX Improvements
- [x] Clickable rows → navigate to session — cursor + onClick for terminal states
- [ ] Bulk actions (cancel multiple running sessions)
- [ ] Session type icons (more visual than text)
- [x] Cost column: color-code by amount (green ≤$1, yellow ≤$5, red >$5)

---

## 14. Session New ✅

### MUI Legacy
- **Agent Runtime**: ToggleButtonGroup (colored by agent), disabled agents with tooltip
- **Model**: Autocomplete (lazy-loaded)
- **Divider "Optional Configuration"**
- Agent Persona, Tools, Skills, MCP Servers, Assets, Repositories (all Autocomplete multiple)
- **Divider "Execution Mode"**
- Mode toggle: Interactive / Automatic
- Initial Prompt (automatic only, required)
- **BMAD Method** switch
- **Start Session** button (colored by agent, large)

### Inertia Current
- Card-based agent selector (color bar + label + status badge) ✅
- Model selector (lazy-loaded) ✅
- Agent Persona selector (Select, server-rendered agents list) ✅
- Tools/Skills/MCP/Assets/Repos MultiSelects (all server-rendered) ✅
- Mode toggle (Interactive/Automatic) ✅, Prompt with char count ✅
- BMAD switch ✅
- Config summary preview card ✅
- Agent-colored Start button ✅
- API POST → redirect to session view ✅
- CSS modules ✅
- Controller passes all resources (agents, tools, skills, mcp_servers, assets, repositories) ✅

### Missing Features
- [x] **Model selector** (Select, lazy-loaded from API)
- [x] **Agent Persona** selector (Select from server-rendered agents)
- [x] **Tools** selector (MultiSelect)
- [x] **Skills** selector (MultiSelect)
- [x] **MCP Servers** selector (MultiSelect)
- [x] **Assets** selector (MultiSelect)
- [x] **Repositories** selector (MultiSelect)
- [x] **Disabled agents** with warning text + tooltip
- [x] **Agent-colored** Start button — color mapped by agent type
- [x] **configured_agent_id** sent to API for persona selection

### UX Improvements
- [x] Agent selection: card-based selector with color bar, label, and setup badge
- [x] Preview: config summary card showing selected agent, mode, model, persona, resource counts, BMAD
- [ ] Quick templates: "Last used configuration", "Default for project"
- [x] Prompt char count for automatic mode

---

## 15. Session View (show) ✅

### MUI Legacy
- **Header**: agent label, state chip, session ID, container ID (12 chars monospace), error message, Finish button, New Session button
- **Terminal**: resizable split (editor 66% / terminal 34%) via react-resizable-panels
- **Editor**: VS Code Server iframe with loading overlay
- **Terminal**: ttyd iframe with loading overlay
- **Collapse**: button on separator, double-click toggle
- **Ended state**: SessionSummaryCard (agent, mode, project, resources, prompt, models, cost, token grid, artifacts)
- **Stopping overlay**: red spinner + "Stopping session…"
- Complete snackbar with "All Sessions" action

### Inertia Current
- Header with back/agent/state/finish/new ✅
- Terminal + IDE iframes (resizable split) ✅
- Collapse editor (button on separator + double-click + ⌘B) ✅
- Loading overlays on iframes ✅
- Container ID + error message in header ✅
- Ended state with rich summary card (agent, mode, duration, tokens grid, cost, models, prompt preview, artifacts) ✅
- Live elapsed timer ✅
- ActionCable ✅ (TerminalSessionChannel → router.reload)
- CSS modules ✅

### Missing Features
- [x] **Resizable split** — react-resizable-panels with drag handle
- [x] **Collapse editor** (button on separator + double-click + ⌘B hotkey)
- [x] **Loading overlays** ("Loading editor...", "Connecting to terminal...") — Overlay + Loader on iframes
- [x] **Container ID** in header (12 chars monospace)
- [x] **Error message** display in header (truncated 300px with tooltip)
- [x] **Stopping overlay** (red spinner) — red Loader + "Stopping session..." overlay
- [x] **SessionSummaryCard** — completion state, agent, mode, duration, token grid (input/output/cache), cost, models, prompt preview, pending outputs
- [ ] **Session complete snackbar** with "All Sessions" action
- [x] **ActionCable** → `router.reload` for live status
- [x] **Review Artifacts button** — navigate to artifacts page when pending outputs

### UX Improvements
- [x] Panel controls: keyboard shortcuts (Cmd+B toggle editor)
- [ ] Terminal fullscreen mode
- [x] Copy session link button — ActionIcon with IconCopy + clipboard + notification
- [x] Time elapsed: live counter (ticks every second while active)

---

## 16. Session Artifacts ✅

### MUI Legacy
- Already reviewed alert
- No artifacts alert
- **Artifact table**: Checkbox (+ select all), File name, Size, Type, Download
- **Actions**: "Save selected (N)" + "Dismiss all"
- Review logic: selected → save, unselected → dismiss
- Success → snackbar + navigate back

### Inertia Current
- Project-level `ArtifactsPage.tsx` ✅ (mirrors company-level pattern)
- Already-reviewed alert ✅, No artifacts alert ✅
- Checkbox table with select all ✅, Download links ✅
- Save selected / Dismiss all ✅, Success notification ✅

### Missing Features (now done)
- [x] Session artifacts review page — `ProjectSessionArtifactsPage`
- [x] Checkbox selection (select all / individual)
- [x] Save selected / Dismiss all actions
- [x] Download individual files
- [x] Post-review redirect

---

## 17. Analytics ✅

### MUI Legacy
- **Filters**: Scope toggle (User/Project), Tags, Task Type, Period (7d/30d/90d/1yr)
- **5 stat cards**: Total Sessions, Total Cost, Total Tokens, Avg Cost/Session, Workflows Run
- **7 charts**: Agent Activity Trend (stacked AreaChart), Agent Type Distribution (donut PieChart), Daily Cost (gradient AreaChart), Daily Token Consumption (gradient AreaChart), Session Source Breakdown (PieChart), Session Duration Histogram (BarChart)
- **Workflow Costs panel**: 7 stat cards + 4 charts + breakdown table

### Inertia Current (663 LOC)
- Scope toggle ✅, Period selector ✅, 5 stat cards ✅
- Agent Activity Trend (stacked AreaChart) ✅, Agent Type Distribution (donut PieChart) ✅
- Daily Cost + Daily Token (gradient AreaCharts) ✅
- Session Source Breakdown (PieChart) ✅, Session Duration Histogram (BarChart) ✅
- Workflow Costs panel: 7 stat cards + 4 charts + breakdown table ✅
- Responsive charts ✅

### Missing Features
- [x] **Scope toggle** (User/Project) — SegmentedControl
- [ ] **Tags filter** (Autocomplete multi-select)
- [ ] **Task Type filter** (Select from API)
- [x] **Session Source Breakdown** chart — PieChart + list
- [x] **Session Duration Histogram** chart — BarChart
- [x] **Workflow Costs panel** — 7 stat cards + 4 charts + breakdown table

### UX Improvements
- [x] Responsive chart sizing — `ResponsiveContainer` + responsive Grid
- [ ] Chart tooltips: more detailed breakdowns
- [ ] Export data (CSV/PDF)
- [ ] Date range picker instead of preset periods
- [ ] Comparison mode (this period vs previous)

---

## 18. Agents ✅

### MUI Legacy
- Table: Agent (emoji + title + name monospace), Scope (project only), Persona (truncated, tooltip), Actions
- Form: Name (regex, monospace, disabled in edit), Icon (EmojiPicker), Title, Persona (multiline 4 rows), Communication Style (multiline 2 rows), Principles (multiline 2 rows)
- Edit/delete guards: company agents show "Company-managed" in project context

### Inertia Current
- Table ✅, Search ✅, Empty state ✅, Scope column ✅, Company-managed indicator ✅
- Form with all fields ✅, EmojiPicker ✅, Duplicate action ✅

### Missing Features
- [x] **"Company-managed" indicator** for inherited agents — disabled Edit/Delete with tooltip
- [x] **Scope column** in project context — conditional Badge column

### UX Improvements
- [ ] Agent card view option (toggle table ↔ cards)
- [ ] Agent preview (persona + style) in expandable row
- [ ] Import/Export agents (JSON)
- [x] Duplicate agent action — IconCopy button pre-fills form with "(Copy)" suffix

---

## 19. Tools ⬜

### MUI Legacy
- Table: Tool (displayName + name), Scope, Docker Image (monospace/"Built-in" chip), Files (chip N files), Actions
- Form 3 tabs: Basic Info (name, displayName, description, dockerImage, command), Files (CodeMirror editor, path must start with /workspace/), Config Items (Autocomplete)
- Scope badges: system=purple, company=gray, project=green, overrides_company=amber

### Inertia Current (303 LOC ToolsContent + 370 LOC ToolFormModal + 75 LOC DeleteModal + 94 LOC ToolFileEditor)
- Table ✅, Search ✅, Kind filter (SegmentedControl) ✅
- 3-tab form ✅, CodeMirror ✅
- Scope badges ✅

### Missing Features
- [x] **Docker Image column** in table (monospace / "Built-in" chip)
- [x] **Files count chip** in table — Badge with count
- [x] File path validation (must start with `/workspace/`) — inline error + submit guard
- [ ] File upload mode (drag zone) vs text mode toggle

### UX Improvements
- [ ] Tool testing: "Test Run" button (dry-run with sample params)
- [ ] Command syntax highlighting
- [ ] File tree view (for tools with many files)

---

## 20. Skills ✅

### MUI Legacy
- Table: Name (monospace), Title, Kind (Internal/Custom), Scope (project only), Description (truncated), Actions
- Form: Name (allows hyphens), Title, Content (multiline 10 rows, max 50000, JetBrains Mono), Description
- Internal skills: not editable

### Inertia Current
- Table ✅, Search ✅, Kind badge ✅, Lock icon for internal ✅
- Form ✅, Monospace content ✅, Max length 50000 ✅

### Missing Features
- [x] **Internal skills**: non-editable indicator (lock icon + tooltip, disabled actions)
- [x] **JetBrains Mono** font for content field — `ff="monospace"`
- [x] **Max length** validation (50000 chars) — Zod `.max(50000)` + `maxLength`

### UX Improvements
- [ ] Content: syntax highlighting (markdown)
- [ ] Preview mode (rendered markdown)
- [ ] Content templates (starter templates for common skill types)

---

## 21. MCP Servers ✅

### MUI Legacy
- Table: Name (displayName + name), URL (truncated), Transport chip (HTTP/SSE/STDIO), Scope, Status (Enabled/Disabled), Actions
- Form: transport-aware (HTTP/SSE → URL + Headers, Stdio → Command + Env vars), ConfigItemValueField toggle, Enabled switch

### Inertia Current
- Table ✅, Search ✅, Transport/scope/status badges ✅, URL column ✅, Enabled/Disabled status ✅
- Transport-aware form ✅, ConfigItemValueField ✅

### Missing Features
- [x] **URL column** in table (truncated)
- [x] **Enabled/Disabled** status display in table — green/gray badges

### UX Improvements
- [ ] Connection test button ("Test Connection" → try connect and report status)
- [ ] Last connected timestamp
- [ ] Health indicator icon (green/red dot)

---

## 22. Config Items ✅

### MUI Legacy
- Table: Name (JetBrains Mono), Type (Secret=red / Variable=blue), Value (masked for secrets), Scope, Description, Actions
- Filters: Search + Type Select (All/Secret/Variable)
- Form: Type toggle (create only), Name (UPPERCASE, auto-transform), Value (password for secrets, visibility toggle), Description
- Edit secrets: "New Value (leave empty to keep current)", not required

### Inertia Current
- Table ✅, Search ✅, Type filter ✅, Masked secrets ✅
- Form ✅, UPPERCASE auto-transform ✅, "New Value (leave empty)" label ✅

### Missing Features
- [x] **Value masked** for secrets ("••••••••")
- [x] **Password visibility toggle** in form — Mantine `PasswordInput` with built-in toggle
- [x] **"New Value (leave empty to keep current)"** label for edit mode
- [x] **UPPERCASE auto-transform** for name field — `onChange` normalizes to `[A-Z0-9_]`

### UX Improvements
- [x] Copy value to clipboard button (for variables) — `CopyButton` with IconCopy/IconCheck
- [ ] Usage indicator (which agents/tools reference this config item)
- [ ] Bulk import from .env file

---

## 23. Integrations 🔵

### MUI Legacy
- **Card layout** (not table)
- Connect menu: GitHub (external URL) / GitLab (PAT dialog)
- Per card: Provider icon, name, "Connected by {name}", status chip, scope chips, Edit (GitHub settings link), Delete
- Project context: separated "This project" + "Company-wide (read-only)"

### Inertia Current
- Card layout ✅, Delete ✅
- Connect menu (GitHub + GitLab coming soon) ✅, "Connected by" ✅, Status chip ✅

### Missing Features
- [x] **Connect menu** (dropdown: GitHub / GitLab — GitLab disabled "coming soon")
- [ ] **GitLab PAT dialog** ("Enter a GitLab Personal Access Token with api scope...")
- [x] **"Connected by" label** on cards — "Connected by {name} · {date}"
- [ ] **Edit button** (GitHub settings link, only for own) — only "GitHub Settings" link, no edit form
- [x] **Status chip** on cards — Badge with `STATUS_COLORS`
- [x] **Project context**: "This project" vs "Company-wide" sections — split with Divider

### UX Improvements
- [ ] Integration health check (last sync status)
- [ ] Visual provider icons (GitHub Octocat, GitLab logo)

---

## 24. Repositories 🔵

### MUI Legacy
- **Card layout**
- Per card: Lock/Public icon, fullName, purpose (italic), branch + integration, scope chip, Edit/Delete
- **Add dialog**: Integration Select + Repository Autocomplete (lock/public icon, fullName, description) + Branch Autocomplete + Purpose TextField
- **Edit dialog**: Branch (Autocomplete freeSolo) + Purpose

### Inertia Current
- Card list ✅, Edit modal with branch Autocomplete ✅
- Lock/Public icon ✅, Integration name ✅

### Missing Features
- [x] **Add dialog** — full flow (Integration select → Repository Autocomplete → Branch → Purpose) — `AddRepositoryModal`
- [x] **Lock/Public icon** on cards — `IconLock` / `IconWorld`
- [x] **Integration name** on card — `{repo.integration.name}`
- [ ] **Already-added repos** disabled in Autocomplete with "added" label
- [x] **Scope chip** on cards — Badge with scope_indicator

### UX Improvements
- [ ] Repository preview (last commit, branch info)
- [ ] Quick clone status indicator

---

## 25. Assets 🔵

### MUI Legacy
- Table: Name (+ source badge), Folder, Size (monospace), Version (v{N} + total), Scope, Date, Actions (Preview, History, Download, Edit, Delete)
- **Upload**: Drag & drop (max 1GB, multiple), progress bar, folder Autocomplete, Uppy + S3 presign
- **Preview**: Multi-format (Markdown rendered, Code/Text monospace, Image centered, Binary download)
- **Version History dialog**: table with version, date, size, type, source, download
- **Soft delete**: 30-day trash with restore

### Inertia Current
- Table ✅, Search ✅, Folder filter ✅, Preview modal ✅
- Upload (Uppy + S3 presign) ✅, Version column (v{N} + count) ✅, Source indicator ✅

### Missing Features
- [x] **Upload** — Uppy + S3 presigned URLs
- [x] **Version column** (v{N} + total count)
- [x] **5 action buttons** — History, Download, Preview, Edit, Delete
- [x] **Version History dialog** — modal with versions table (fetched from API)
- [x] **Source badge** (upload/session/workflow) — dimmed text under name
- [x] **Soft delete** confirmation — "moved to trash, restore within 30 days" modal
- [x] **Multi-format preview** — images, text/code in Code block, PDF message, generic download

### UX Improvements
- [ ] Grid/list view toggle
- [ ] Drag & drop reorder in folders
- [ ] Asset diff viewer (compare versions)
- [ ] Bulk download as zip

---

## 26. Company Members ✅

### MUI Legacy
- **Filters**: Search (debounced 300ms) + Role (All/Admin/Employee) + Status (All/Active/Pending/Archived)
- **Table**: User (name + email), Role chip, Status chip, Invited (date + "by {name}" / "Self-registered"), Actions (MoreVert context menu)
- **Context menu**: Archive, Activate, Make Admin, Make Employee (with guards: last admin disabled), Delete (window.confirm)
- **Invite dialog**: Email, Name, Role (Employee/Admin)
- **Pagination**: 10/25/50 per page, server-side

### Inertia Current
- Table ✅, Search ✅, Role filter ✅, Status filter ✅, Avatars ✅
- Status chips (colored) ✅, Invited by ✅, Context menu ✅, Invite modal ✅

### Missing Features
- [x] **Role filter** (All/Admin/Employee)
- [x] **Status filter** (All/Active/Pending/Archived)
- [x] **Status chip** in table (active=green, pending=yellow, archived=gray, suspended=red)
- [x] **Invited by** column (date + "by {name}" or "Self-registered")
- [x] **Context menu actions**: Archive, Activate, Make Admin/Employee, Remove
- [x] **Last admin guard** ("Cannot modify the last admin") — disabled menu items + tooltip
- [ ] **Pagination** (server-side, 10/25/50 per page)

### UX Improvements
- [x] Avatar in the user column — initials Avatar
- [ ] Activity indicator (last active date)
- [ ] Bulk invite (paste multiple emails)

---

## 27. User Profile ✅

### MUI Legacy
- **Profile Form**: Email (read-only, LockIcon, tooltip), Display Name, Language (11 options), Company (read-only), Role badge, Save button (disabled when not dirty)
- **Default Agent Runtime**: Card with Select of configured credentials
- **Default Models**: Per credential Autocomplete (lazy-loaded models)
- **Agent Credentials**: Per agent (4): card with color bar, status icon, name, description, metadata (configured/last used/expires), "Connected" chip, Re-authenticate / Authenticate button
- **Auth Terminal Flow**: Full-screen dialog with xterm.js, auth polling 2s, "Save Authentication" button

### Inertia Current
- Profile form ✅ (email with lock tooltip, name, language, company read-only, role badge)
- Default Agent selector ✅, Default Models selector ✅
- Agent credentials with metadata ✅, "Connected" chip ✅
- Save disabled when not dirty ✅

### Missing Features
- [x] **Company** read-only field
- [x] **Role badge** (ROLE_COLORS + ROLE_LABELS)
- [x] **Email lock tooltip** — IconLock + Tooltip
- [x] **Agent credential metadata**: configured date, last used, expires
- [x] **"Connected" chip** (green outline Badge)
- [ ] **Re-authenticate flow**: full-screen dialog with xterm.js terminal — button links to API URL, no embedded terminal
- [ ] **Auth polling** (2s interval until auth detected)
- [x] Save button disabled when not dirty / not valid

### UX Improvements
- [ ] Profile photo / avatar upload
- [ ] Section cards with visual separation (Profile / Defaults / Credentials)
- [ ] Credential expiry warnings
- [ ] Quick actions: "Re-authenticate all expired"

---

## 28. Project Settings ✅

### MUI Legacy
- Edit project name + description, save button

### Inertia Current
- Form with name + description ✅, Zod validation (name required max 100, desc max 500) ✅
- Save button ✅

### Missing Features
- [x] Verify validation (name required, max length) — Zod schema

### UX Improvements
- [x] Project archive/delete actions — Archive + Delete buttons in Danger Zone
- [ ] Project icon/color selector
- [x] Danger zone section (archive, delete) — red-bordered Paper with confirmation modals

---

## 29. Project Members ✅

### MUI Legacy
- List collaborators
- Add from company users (Autocomplete)
- Remove with confirmation
- Only project owner can manage

### Inertia Current
- Member list with avatars ✅, Add collaborator ✅, Remove with confirm ✅, Owner badge ✅

### Missing Features
- [ ] **Owner-only management** guard (verify: only owner sees add/remove)
- [x] **Confirmation dialog** on remove — `confirm()` before `router.delete`

### UX Improvements
- [x] Role indicators (Owner, Member) — Owner badge with crown icon
- [ ] Transfer ownership option

---

## Summary

### Feature Parity Status

| Category | Pages | Feature Parity | Status |
|----------|-------|---------------|--------|
| Shell (Header, Sidebar) | 1 | ~98% | ✅ |
| Auth (Login, Onboarding) | 2 | ~95% | ✅ (step animation pending) |
| Projects (List, Overview, Settings, Members) | 4 | ~95% | ✅ (sparklines, thumbnails pending) |
| Board (Kanban) | 1 | ~93% | ✅ (view presets, WIP limits, spring physics pending) |
| Workflows (List, Builder, Runs, Run Modal) | 4 | ~75% | 🔵 (Builder not started, AixleBanner pending) |
| Aixle Builder | 1 | 0% | ⬜ (Phase 5) |
| Sessions (List, New, View, Artifacts) | 4 | ~90% | ✅ (collapse editor, snackbar pending) |
| Analytics | 1 | ~95% | ✅ (tags/type filters, export pending) |
| CRUD (Agents–Assets) | 8 | ~93% | ✅ (GitLab PAT, asset grid view pending) |
| User Management (Members, Profile) | 2 | ~92% | ✅ (pagination, re-auth terminal pending) |
| **Total** | **29** | **~91%** | **26/29 ✅** |

### Remaining Items (deferred / Phase 5)

1. **Workflow Builder** — not started (Phase 5, very complex — full split-panel editor)
2. **Aixle Builder** — not started (Phase 5, complex — landing page + session view)
3. **DAG Timeline** for Workflow Run (horizontal wave grouping — significant UI effort)
4. **Terminal panel** in Workflow Run Show (embed xterm.js for step sessions)
5. **Server-side pagination** for Sessions and Members lists
6. **Re-authenticate terminal flow** for Profile (full-screen xterm.js dialog)
7. Minor UX polish: sparklines, step animation, spring physics, bulk actions, export CSV
