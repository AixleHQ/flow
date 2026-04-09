# Legacy SPA Frontend — Complete Functionality Audit

> **Purpose:** Comprehensive documentation of every feature, component, interaction, and data flow in the original SPA frontend (TanStack Router + MUI + RTK Query) before the Inertia/Mantine rewrite.
>
> **Created:** 2026-04-03
> **Stack:** React 18, TanStack Router, Material UI v5, RTK Query (Redux Toolkit), notistack, Recharts, xterm.js, DnD Kit, react-hook-form + Zod, Action Cable WebSockets

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Application Shell & Layouts](#2-application-shell--layouts)
3. [Authentication & Onboarding](#3-authentication--onboarding)
4. [Projects](#4-projects)
5. [Project Page — Tabbed Interface](#5-project-page--tabbed-interface)
6. [Board (Kanban Task Management)](#6-board-kanban-task-management)
7. [Workflows](#7-workflows)
8. [Workflow Builder](#8-workflow-builder)
9. [Workflow Runs](#9-workflow-runs)
10. [Aixle Builder (AI Project Builder)](#10-aixle-builder-ai-project-builder)
11. [Terminal Sessions](#11-terminal-sessions)
12. [Session Artifacts](#12-session-artifacts)
13. [Analytics & Cost Tracking](#13-analytics--cost-tracking)
14. [Project Overview Dashboard](#14-project-overview-dashboard)
15. [Agents Management](#15-agents-management)
16. [Tools Management](#16-tools-management)
17. [Skills Management](#17-skills-management)
18. [MCP Servers Management](#18-mcp-servers-management)
19. [Config Items (Secrets & Variables)](#19-config-items-secrets--variables)
20. [Integrations Management](#20-integrations-management)
21. [Repositories Management](#21-repositories-management)
22. [Assets Management](#22-assets-management)
23. [Company Members](#23-company-members)
24. [User Profile](#24-user-profile)
25. [Agent Credentials & Authentication](#25-agent-credentials--authentication)
26. [Shared UI Components](#26-shared-ui-components)
27. [State Management & API Layer](#27-state-management--api-layer)
28. [Real-Time Features (WebSockets)](#28-real-time-features-websockets)
29. [Routing & Navigation](#29-routing--navigation)
30. [Data Models Reference](#30-data-models-reference)

---

## 1. Architecture Overview

### Tech Stack
| Layer | Technology |
|-------|-----------|
| UI Framework | Material UI (MUI) v5 with custom dark theme |
| Routing | @tanstack/react-router with typed params |
| State Management | RTK Query (Redux Toolkit) — server state only |
| Forms | react-hook-form + Zod validation schemas |
| Notifications | notistack (snackbar, top-right, 1500ms auto-hide) |
| Charts | Recharts (area, bar, pie charts) |
| Terminal | xterm.js + fit addon + web-links addon |
| Drag & Drop | DnD Kit (sortable) |
| Real-time | Action Cable (Rails) WebSocket channels |
| Error Tracking | Sentry (browser SDK) |
| API Communication | Axios (via RTK Query base query) with CSRF, camelCase ↔ snake_case auto-conversion |
| Code Editor | VS Code Server (embedded iframe) |
| Entry Point | `entrypoints/application.tsx` → `app/App.tsx` |

### Feature-Slice Design Structure
```
app/frontend/
├── entrypoints/          — Application bootstrap (Sentry init, createRoot)
├── app/                  — SPA shell (App.tsx, routeTree.tsx, layouts, providers)
├── pages/                — Route-level page components (thin orchestrators)
├── features/             — Domain feature modules (API + UI + lib per slice)
├── widgets/              — App-level composite widgets (header, sidebar, session, etc.)
├── entities/             — Thin domain layer (types, small UI, entity APIs)
├── shared/
│   ├── api/              — RTK store, baseApi, generated routes, domain APIs
│   ├── theme/            — MUI theme (palette, typography, component overrides)
│   ├── ui/               — Shared UI components (Loader, Logo, Terminal, etc.)
│   ├── lib/              — Utilities, hooks, Sentry, Action Cable
│   ├── model/            — LLM types
│   └── routes.ts         — Frontend + backend path helpers
└── types/generated/      — Typelizer-generated TypeScript types
```

### Provider Stack (outer → inner)
1. `Sentry.ErrorBoundary` — global error boundary with dialog
2. `Redux Provider` — RTK Query store
3. `MUI ThemeProvider` — custom dark theme + CssBaseline
4. `SnackbarProvider` — notistack (max 3, top-right)
5. `React.Suspense` — LinearProgress fallback
6. `RouterProvider` — TanStack Router (scroll restoration, preload on intent)

---

## 2. Application Shell & Layouts

### Root Layout (`app/layouts/RootLayout.tsx`)
- Renders `<RoutePendingIndicator />` (top LinearProgress bar during route transitions) + `<Outlet />`
- Wraps all routes as the outermost shell

### Auth Layout (`app/layouts/AuthLayout/AuthLayout.tsx`)
- Wraps all authenticated routes (everything except `/login`)
- **Auth guard logic:**
  - No user → redirect to `/login`
  - User not onboarded → redirect to `/onboarding`
  - Onboarded user on onboarding page → redirect to `/company/projects`
  - While loading → shows `<Loader />`

- **Chrome structure (when authenticated):**
```
┌─────────────────────────────────────────────┐
│  AppHeader (top bar, project selector)       │
├──────┬──────────────────────────────────────┤
│      │                                       │
│ App  │   <main> <Outlet /> </main>           │
│ Side │                                       │
│ bar  │                                       │
│      │                                       │
│      ├──────────────────────────────────────┤
│      │   footer: "Powered by [Logo]"         │
└──────┴──────────────────────────────────────┘
```

### AppHeader (`widgets/AppHeader/`)
| Element | Description |
|---------|-------------|
| Company logo | Links to `/company/projects` |
| Project selector | Dropdown listing all projects; selected project persisted in `localStorage` |
| "Work" menu | Sessions, Workflows, Assets |
| "Agent Context" menu | Agents, Tools, MCP Servers, Skills |
| "Settings" menu | Integrations, Repositories, Secrets & Variables, Members (admin-only items hidden for non-admins) |
| User section | Avatar (initials), name, dropdown: "My Profile", "Sign Out" |

### AppSidebar (`widgets/AppSidebar/`)
- Only visible on project routes (`/company/projects/:id/...`)
- Collapsible: 220px ↔ 56px (persisted in `localStorage` key `sidebar-collapsed`)
- **Navigation groups:**

| Group | Tabs |
|-------|------|
| Primary | Overview, Tasks (board), Sessions, Workflows, Runs, Assets, Analytics |
| Configuration | Repositories, Integrations, Agents, Tools, MCP Servers, Skills |
| Admin | Secrets & Variables, Config, Members, Settings |

---

## 3. Authentication & Onboarding

### Login Page (`pages/login/`)
**Route:** `/login`

**Functionality:**
- Email + password login via `POST /api/v1/sessions`
- Google OAuth login (full page redirect to `/api/v1/auth/google`)
- Auto-redirect if already authenticated (to projects or onboarding based on state)
- OAuth error handling via URL search params (`pending_approval`, `deactivated`, `oauth_failed`, `oauth_error`)

**UI Elements:**
- Centered card with Logo
- Email text field + Password text field
- "Sign In" submit button
- "OR" divider
- "Sign in with Google" button
- Snackbar notifications for errors

**Validation:** Zod schema (email required, password required)

---

### Onboarding Page (`pages/onboarding/`)
**Route:** `/onboarding`

**4-Step Wizard:**

| Step | Title | UI | Actions |
|------|-------|----|---------|
| 1. Profile | Set up your profile | Position dropdown (Dev/QA/PM/Designer/CTO), Language dropdown (11 languages) | Auto-save with 300ms debounce |
| 2. Agents | Select your agents | 2×2 grid of agent cards (Claude Code, Cursor CLI, Codex, Gemini CLI) with checkboxes | Toggle agent selection (auto-saved) |
| 3. Authenticate | Authenticate agents | Agent list sidebar + embedded `AgentAuthTerminal` | Complete terminal-based auth flow per agent |
| 4. Complete | All set! | Summary card with profile + agent statuses | "Go to Dashboard" button |

**Special Behavior:**
- Backend AASM state machine controls step transitions (`go_next`, `go_previous`, `complete` events)
- Step 3 polls `refetch()` every 500ms (max 20 attempts) waiting for Temporal workflow to save credentials
- Progress bar with numbered step indicators
- `isUserChange` ref prevents false auto-saves during initial data load

---

## 4. Projects

### Projects List Page (`pages/projects/`)
**Route:** `/company/projects`

**Functionality:**
- Display all company projects in a responsive 3-column grid of `ProjectCard` components
- Client-side search/filter by project name and description
- Create new project via dialog (name + description fields)

**UI Elements:**
- Header: "Projects" title + "Create Project" button
- Search text field (client-side filtering)
- Grid of `ProjectCard` components:
  - Project name
  - Description (2-line clamp)
  - Collaborator chip + count
  - "Last activity" relative timestamp
- Empty states (no projects, no search results)
- `CreateProjectDialog` modal

**API:** `GET /api/v1/company/projects`, `POST /api/v1/company/projects`

---

## 5. Project Page — Tabbed Interface

### Project Page (`pages/project/`)
**Route:** `/company/projects/:projectId/:tab`
**Default redirect:** `/company/projects/:projectId` → `…/overview`

The main project workspace with **16 tabs**, each rendering a different feature panel:

| Tab slug | Tab name | Component | Feature module |
|----------|----------|-----------|----------------|
| `overview` | Overview | `ProjectOverviewPanel` | `features/project-overview` |
| `board` | Tasks | `BoardPanel` | `features/board-management` |
| `workflows` | Workflows | `WorkflowsPanel` + `ConnectedRunModal` | `features/workflows` + `features/run-workflow` |
| `workflow-runs` | Runs | `WorkflowRunsWidget` | `widgets/workflow-runs` |
| `assets` | Assets | `AssetsPanel` + `AssetPreview` | `features/assets-management` + `features/asset-preview` |
| `sessions` | Sessions | `SessionHistoryWidget` + "New Session" button | `widgets/session-history` |
| `members` | Members | `MembersTab` (inline) | — |
| `config` | Config | `ConfigItemsPanel` | `features/config-items-management` |
| `agents` | Agents | `AgentsPanel` | `features/agents-management` |
| `tools` | Tools | `ToolsPanel` | `features/tools-management` |
| `mcp-servers` | MCP Servers | `McpServersPanel` | `features/mcp-servers-management` |
| `skills` | Skills | `SkillsPanel` | `features/skills-management` |
| `repositories` | Repositories | `RepositoriesPanel` | `features/repositories-management` |
| `integrations` | Integrations | `IntegrationsPanel` | `features/integrations-management` |
| `settings` | Settings | `SettingsTab` (inline) | — |
| `analytics` | Analytics | `ProjectAnalyticsPanel` | `features/project-analytics` |

**Search params (Board tab):** `assigneeId`, `taskType`, `priority`, `tags`, `search`, `task` (task ID for deep-link)

### Inline Tabs

**MembersTab:** List project collaborators, add from company users (Autocomplete), remove with confirmation. Only project owner can manage.

**SettingsTab:** Edit project name + description, save button.

---

## 6. Board (Kanban Task Management)

### Feature: `features/board-management/`

**The most complex feature in the application.** Full kanban board with drag-and-drop, filtering, task detail sidebar, comments, assets, activity log, statistics, and workflow triggers.

### Board Panel
- Horizontal scrollable kanban columns
- Drag-and-drop tasks between columns (DnD Kit)
- **Optimistic updates** on task move (instant UI, server sync in background)
- Board creation from presets when no board exists
- Filter bar and view preset management

### Board Filters
| Filter | Type | Description |
|--------|------|-------------|
| Assignee | Dropdown | Filter by project member |
| Task Type | Dropdown | Epic / Story / Bug / Not specified |
| Priority | Dropdown | Critical / High / Medium / Low |
| Tags | Multi-select | Free-text tag filter |
| Search | Text field | Full-text task search |
| View Presets | Save/Load | Persist filter combinations |

### Task Card (Kanban card)
- Priority indicator dot (color-coded: critical=red, high=orange, medium=yellow, low=green)
- Task title
- Workflow status dots (animated pulse for active states, yellow for pending waits)
- Task type chip (color-coded: epic=purple, story=blue, bug=red)
- Tags (max 3 shown + overflow count)
- Assignee avatar (initials)
- Comments count badge

### Task Detail Sidebar (Zustand store: `useBoardSidebarStore`)
5 tabs within the sidebar:

| Tab | Content |
|-----|---------|
| **Details** | Editable: title, description, task type dropdown, priority dropdown, assignee dropdown, tags (Autocomplete), parent task |
| **Comments** | Comment feed with tag filtering (feedback, tech_design, code_review, qa_report, implementation_notes), add new comment |
| **Assets** | File list, upload new files, delete files |
| **Activity** | Paginated activity log (task creation, status changes, moves, assignments, comments) |
| **Statistics** | Per-task cost/token/time breakdown, workflow run history, wait analysis |

### Board Settings
- Manage columns (add, rename, delete, reorder)
- Workflow bindings per column (auto-trigger workflow when task enters column)
  - Trigger modes, cooldown configuration
- Delete board (with confirmation)

### Task Actions
| Action | Description |
|--------|-------------|
| Create task | Dialog with title, description, type, priority, assignee, tags |
| Move task | Drag between columns or use move endpoint |
| Edit task | Inline editing in sidebar |
| Delete task | Confirmation dialog |
| Trigger workflow | Start a workflow run on a specific task |
| View workflow runs | See all workflow runs triggered for this task |
| Add/remove comments | With tag support |
| Upload/delete assets | File attachments per task |
| Delete waits | Remove external blocking waits (PR, workflow) |

### Real-Time Updates
- **Action Cable `BoardChannel`** subscription by `board_id`
- Events: `board_task.created`, `board_task.updated`, `board_task.destroyed`, `board_activity.created`
- Defers refetch during in-flight drag operations to prevent UI snapping

### API Endpoints (Board)
```
GET    .../board                           — Board with all columns and tasks
POST   .../board                           — Create board (with optional preset)
PATCH  .../board                           — Update board settings
DELETE .../board                           — Delete board
GET    .../board/presets                    — Available board presets
POST/PATCH/DELETE .../board/columns         — Column CRUD
PATCH  .../columns/reorder                 — Reorder columns
POST/PATCH/DELETE .../columns/:id/workflow_binding — Column workflow bindings
GET    .../board/activities                — Board-level activity feed
GET/POST/DELETE .../board/view_presets     — View preset management
POST/PATCH/DELETE .../board/tasks          — Task CRUD
GET    .../board/tasks/:id                 — Task detail
PATCH  .../tasks/:id/move                  — Move task (column + position)
POST   .../tasks/:id/trigger_workflow      — Trigger workflow on task
GET    .../tasks/:id/workflow_runs         — Task workflow runs
GET/POST .../tasks/:id/comments            — Comments CRUD
GET/POST/DELETE .../tasks/:id/assets       — Task file attachments
DELETE .../tasks/:id/waits/:id             — Remove wait
GET    .../tasks/:id/transitions           — Task column transitions history
GET    .../tasks/:id/activities            — Task-level activity log
GET    .../tasks/:id/statistics            — Task cost/token statistics
```

---

## 7. Workflows

### Feature: `features/workflows/`

### Workflows Panel
- Lists all workflows (company-level or project-level depending on context)
- Table with: name, description, steps count, last run date/status, active runs indicator
- Create, edit, delete, duplicate workflows

### Create/Edit Dialog
- Name field
- Description field (optional)
- Scope badge (company vs project)

### Duplicate to Project
- Copy a company-level workflow to a specific project for customization

### API Endpoints
```
GET/POST   .../company/workflows           — Company-level CRUD
GET/PATCH/DELETE .../company/workflows/:id
GET/POST   .../projects/:id/workflows      — Project-level CRUD
GET/PATCH/DELETE .../projects/:pid/workflows/:id
POST       .../workflows/:id/duplicate     — Duplicate to project
```

---

## 8. Workflow Builder

### Page: `pages/workflow-builder/`
**Routes:**
- `/company/workflows/:workflowId/builder` (company-level)
- `/company/projects/:projectId/workflows/:workflowId/builder` (project-level)

**The second most complex page.** Full workflow editor with step configuration, dependency management, and resource assignment.

### Layout
```
┌─────────────────────────────────────────────────┐
│  [← Back]  Workflow Name (editable) [Run ▶]      │
│            Description (editable)                 │
├──────────────┬──────────────────────────────────┤
│              │                                    │
│  Step List   │   Step Detail Panel               │
│  (sidebar)   │   or                              │
│              │   Base Resources Section           │
│  [+ Add]     │                                    │
│              │                                    │
└──────────────┴──────────────────────────────────┘
```

### Base Resources Section (Accordion)
- "Inherit all project resources" toggle
- Base tools selector (multi-select Autocomplete)
- Base skills selector (multi-select Autocomplete)
- Base MCP servers selector (multi-select Autocomplete)
- Base assets selector (multi-select Autocomplete)

### Step List (Left Sidebar)
- Ordered list of step cards showing: position number, name, agent type badge, tags (runtime, auto-run, BMAD, dependency count)
- Reorder arrows (up/down)
- "Add Step" button
- Click to select/edit step

### Step Detail Panel (Right)
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Step name |
| Description | Text | Brief description |
| Instructions | Multi-line text | Detailed instructions for the agent |
| Agent | Dropdown | Select agent persona |
| Required Runtime | Dropdown | Agent runtime type (claude_code, cursor_cli, etc.) |
| Preferred Model | Dropdown | LLM model (lazy-loaded per runtime) |
| Execution: Auto-run | Toggle | Run automatically without human interaction |
| Execution: Skip Policy | Dropdown | When to skip this step |
| Execution: On Failure | Dropdown | Retry / Skip / Stop workflow |
| Execution: Max Retries | Number | Max retry attempts (when on_failure=retry) |
| Tools | Multi-select | Assigned tools |
| MCP Servers | Multi-select | Assigned MCP servers |
| Skills | Multi-select | Assigned skill documents |
| Mount Repositories | Toggle | Mount connected repos in workspace |
| BMAD Method | Toggle | Enable BMAD methodology |
| Dependencies | Multi-select | Steps that must complete before this step runs |
| Sub-steps | Ordered list | Nested sub-steps with CRUD + reorder |
| Input Asset Specs | List | Expected input files (name, description, required) |
| Output Asset Specs | List | Expected output files (name, description, required) |
| Delete Step | Button | Remove step with confirmation |

### Auto-Save Behavior
- All text fields use 500ms debounce
- `useGuardedDraftSync` hook prevents stale server data from overwriting in-flight edits
- Toggle/dropdown changes save immediately

### Scope-Aware Behavior
- Company-level workflows: full edit access
- Viewing company workflow from project context: read-only mode with "Copy & Configure" option
- Project-level workflows: full edit access

---

## 9. Workflow Runs

### Workflow Run Page (`pages/workflow-run/`)
**Route:** `/company/projects/:projectId/workflow-runs/:runId`

### Run Workflow Modal (`features/run-workflow/`)
Launched from the Workflow Builder or Workflows panel.

| Field | Description |
|-------|-------------|
| Execution mode | Interactive / Automatic / Custom (per-step auto-run toggles) |
| Agent runtime | Select from user's configured agent credentials |
| Repositories | Multi-select of connected repositories to mount |
| Input assets | Multi-select, grouped by folder |
| Step visualization | DAG-based dependency wave preview |

### Workflow Run Page Layout
```
┌──────────────────────────────────────────────────┐
│  ← Back   Workflow: [name]   [State badge]       │
│  Duration: 00:05:23   Steps: 3/5   [Cancel ✕]    │
├──────────────────────────────────────────────────┤
│  [Steps]  [Workflow Assets]                       │
├──────────────────────────────────────────────────┤
│                                                    │
│  DAG Timeline (horizontal wave-based step chips)  │
│  ●──●──●  ●──●                                   │
│                                                    │
├──────────────────────────────┬───────────────────┤
│                              │   Sub-steps list   │
│   Terminal (xterm.js or      │   Action buttons:  │
│   VS Code iframe)            │   - Approve        │
│                              │   - Skip (reason)  │
│                              │   - Retry          │
│                              │   - Finish Session │
├──────────────────────────────┴───────────────────┤
│  StatusBar: agent | cost | duration | user        │
└──────────────────────────────────────────────────┘
```

### Step States & Actions
| State | Visual | Available Actions |
|-------|--------|-------------------|
| `pending` | Gray clock | — |
| `running` | Blue play (pulse animation) | View terminal |
| `waiting_input` | Yellow pause | Approve & Continue, Skip (with reason), Finish Session |
| `completed` | Green check | — |
| `failed` | Red error | Retry |
| `skipped` | Gray skip | — |

### Workflow Run States
| State | Description |
|-------|-------------|
| `pending` | Queued, not yet started |
| `running` | Active execution |
| `paused` | Waiting for human input on a step |
| `completed` | All steps finished successfully |
| `failed` | A step failed (depending on on_failure policy) |
| `cancelled` | Manually cancelled by user |

### Workflow Assets Tab
- Lists all output assets from all completed steps
- Per-asset: name, step origin, file size, download button
- "Export to Project" — save individual asset or export all to project assets (with folder/tags configuration)

### Real-Time Updates
- **`useWorkflowRunChannel`** — Action Cable subscription for run state changes
- **Live timer** — `useTick(isActive)` updates duration every second
- **DAG visualization** — computed from step `dependsOnStepIds`, groups into parallel waves

### API Endpoints
```
GET    .../workflow_runs/:id                — Run details with step runs
POST   .../workflow_runs                    — Create new run
POST   .../workflow_runs/:id/approve_step   — Approve waiting step
POST   .../workflow_runs/:id/retry_step     — Retry failed step
POST   .../workflow_runs/:id/skip_step      — Skip step (with reason)
POST   .../workflow_runs/:id/cancel         — Cancel entire run
GET    .../workflow_runs/:id/workflow_run_assets — List output assets
POST   .../workflow_run_assets/:id/export   — Export single asset
POST   .../workflow_run_assets/export_all   — Export all assets
```

### Workflow Runs Widget (`widgets/workflow-runs/`)
- Project-scoped table with state filter (Running/Completed/Failed/Cancelled/Pending)
- Columns: status icon, workflow name + ID, mode, step progress, duration, started time
- 10s polling interval
- Click to navigate to run detail page

---

## 10. Aixle Builder (AI Project Builder)

### Feature: `features/aixle-builder/` + `pages/aixle-builder/`

Three sub-pages for the AI-powered project setup tool:

### Landing Page (`/company/projects/:projectId/aixle-builder`)
| Element | Description |
|---------|-------------|
| Hero section | Icon, title ("Aixle Builder"), description |
| Agent runtime | Dropdown of user's configured agents |
| Model selector | Optional model override (lazy-loaded per runtime) |
| Project assets | Multi-select of existing project assets to feed builder |
| Start button | "Start Builder" or "Continue Active Session" |
| Previous sessions table | ID, status chip, runtime, started date |

### Run-based View (`/company/projects/:projectId/aixle-builder/:runId`)
Split layout:
- **Left:** Terminal panel (agent workspace)
- **Right:** Three tabs:
  - **Activity:** `MetaActivityLog` — real-time log of entities being created (workflows, board columns, tasks, etc.)
  - **Workflow:** `WorkflowPreview` — preview of workflow being built
  - **Board:** `BoardPreview` — preview of kanban board being set up

### Session-based View
Similar layout but uses `useTerminalSession` hook directly. Shows `WorkflowsListPreview` for multiple workflows.

### Real-Time Features
- **`useMetaActivityChannel`** — Action Cable subscription to `TerminalSessionChannel`
- Event: `meta_activity` — entity creation events during builder session
- Merges persisted activities from session metadata with live WebSocket events

### API Endpoints
```
POST  .../aixle_builder/start    — Start builder session
GET   .../aixle_builder/status   — List builder sessions
```

---

## 11. Terminal Sessions

### Session Launch Widget (`widgets/session-launch/`)
Full session creation form with all configuration options.

**Form Fields:**
| Field | Type | Description |
|-------|------|-------------|
| Agent Runtime | Toggle group | Claude Code, Cursor CLI, Codex, Gemini CLI (disabled if not configured) |
| Model | Dropdown | LLM model (lazy-loaded per agent type) |
| Agent Persona | Autocomplete | Select agent persona |
| Tools | Multi-select | Available tools (company + project) |
| Skills | Multi-select | Available skills (company + project) |
| MCP Servers | Multi-select | Available MCP servers (company + project) |
| Assets | Multi-select | Available assets (company + project) |
| Repositories | Multi-select | Connected repositories |
| Execution Mode | Toggle | Interactive / Automatic |
| Initial Prompt | Text area | Required for automatic mode |
| BMAD Method | Switch | Enable BMAD methodology |
| Start Session | Button | Creates session and transitions to active view |

**Active Session View:**
- Header bar: agent label, state chip, session ID, container ID
- Finish button + New Session button
- Terminal + Editor (via `TerminalSessionWidget`)
- Stopping overlay → ended message on completion

### Terminal Session Widget (`widgets/terminal-session/`)
Dual-pane iframe widget:

```
┌─────────────────────┬──────────────────┐
│                     │                  │
│  VS Code Server     │  ttyd Terminal   │
│  (iframe)           │  (iframe)        │
│                     │                  │
│  [collapse ←]       │                  │
└─────────────────────┴──────────────────┘
         ↕ resizable (react-resizable-panels)
```

- Editor panel: VS Code Server iframe (`session.ideUrl`)
- Terminal panel: ttyd terminal (`session.websocketUrl` converted to HTTPS)
- Resizable split with collapse button
- State screens: loading, error, not ready, finished/failed

### Session History Widget (`widgets/session-history/`)
Paginated sessions table:

| Column | Content |
|--------|---------|
| ID | Session identifier |
| Agent | Colored chip (claude_code=red, cursor_cli=blue, etc.) |
| Type | Standalone / Workflow step / Auth setup / Tool setup |
| Status | State chip (running=blue, ready=green, finished=gray, failed=red) |
| User | Session creator |
| Project | Project name (if not project-scoped) |
| Tokens | Total with tooltip breakdown (input/output/cache) |
| Cost | Cost in cents |
| Models | Model chips |
| Duration | Elapsed time |
| Started | Relative timestamp |
| Action | Open in new tab (for ready sessions) |

**Filters:** Agent type dropdown, State dropdown. 20 per page. 15s polling interval.

### Session View Page (`pages/company-sessions/`)
**Routes:**
- `/company/sessions` — List (SessionHistoryWidget)
- `/company/sessions/new` — New session (SessionLaunchWidget + TerminalSessionWidget)
- `/company/sessions/:sessionId` — View session
- `/company/projects/:projectId/sessions/new` — Project-scoped new session
- `/company/projects/:projectId/sessions/:sessionId` — Project-scoped view

**View Page (active session):**
- Full TerminalSessionWidget with editor + terminal

**View Page (ended session):**
- "Session finished/failed" message
- `SessionSummaryCard` (agent, mode, project, resource counts, prompt, model, cost, token breakdown, artifacts info)
- "Review Outputs" button (if pending artifacts)
- Navigation buttons (back, new session)

### Session Summary Card
| Section | Content |
|---------|---------|
| Agent | Runtime chip + mode chip |
| Resources | Repos count, tools count, skills count, MCP count |
| Prompt | Initial prompt (truncated to 200 chars) |
| Models | Model chips + total cost |
| Tokens | Grid: input, output, cache_read, cache_write with totals |
| Artifacts | Logs count, pending outputs count, review status |

### API Endpoints
```
POST   /api/v1/terminal_sessions           — Create session
GET    /api/v1/terminal_sessions/:id        — Get session details
PATCH  /api/v1/terminal_sessions/:id        — Update session
POST   /api/v1/terminal_sessions/:id/finish — Finish session
DELETE /api/v1/terminal_sessions/:id        — Delete session
GET    /api/v1/terminal_sessions            — List sessions (global)
GET    .../company/terminal_sessions        — List company sessions
GET    .../projects/:id/terminal_sessions   — List project sessions
```

---

## 12. Session Artifacts

### Page: `pages/session-artifacts/`
**Routes:**
- `/company/sessions/:sessionId/artifacts`
- `/company/projects/:projectId/sessions/:sessionId/artifacts`

**Functionality:**
- Review output files from completed agent sessions
- Select which artifacts to save to project assets vs dismiss

**UI Elements:**
| Element | Description |
|---------|-------------|
| Alert | Shown if artifacts already reviewed |
| Table | Checkbox, file name (with icon), size, content type, download link |
| Select all | Header checkbox for bulk selection |
| Actions | "Save selected (N)" button + "Dismiss all" button |

**User Actions:**
- Toggle individual artifact selection
- Select/deselect all
- Download individual artifacts
- Save selected to project assets
- Dismiss all artifacts

### API Endpoints
```
GET    .../terminal_sessions/:id/artifacts  — List artifacts
POST   .../terminal_sessions/:id/artifacts/review — Submit review decisions (save/dismiss per artifact)
GET    .../terminal_sessions/:id/artifacts/:id/download — Download artifact
```

---

## 13. Analytics & Cost Tracking

### Project Analytics Panel (`features/project-analytics/`)
**Tab:** `analytics` within Project Page

Full analytics dashboard with 7 chart panels:

#### Summary Stats (Top row of cards)
- Total sessions count
- Total cost (formatted as currency)
- Total tokens (formatted with suffixes)
- Average cost per session
- Total workflow runs

#### Charts
| Chart | Type | Data |
|-------|------|------|
| Agent Activity | Stacked area (Recharts) | Sessions over time by agent type |
| Agent Type Distribution | Pie chart | Breakdown by agent type |
| Cost Over Time | Area chart | Daily cost |
| Token Consumption | Area chart | Daily token usage (input/output) |
| Session Source Distribution | Pie chart | By source (standalone, workflow, etc.) |
| Session Duration Distribution | Bar histogram | Buckets of session duration |

#### Workflow Cost Analytics (embedded `WorkflowCostsPanel`)
| Chart/Table | Type | Data |
|-------------|------|------|
| Summary stats | Cards | Total cost, tokens, workflow count, avg cost/time |
| Cost over time | Area chart | Time series of workflow costs |
| Token consumption | Area chart | Time series of tokens |
| Cost per workflow | Horizontal bar chart | Top workflows by cost |
| Tokens per workflow | Stacked bar chart | Input/output tokens per workflow |
| Detailed table | Data table | Per-workflow breakdown: cost, tokens, runs, avg/total time |

#### Filters
| Filter | Type | Options |
|--------|------|---------|
| Scope | Toggle | User / Project |
| Period | Dropdown | 7 days / 30 days / 90 days / 1 year |
| Tags | Multi-select Autocomplete | Dynamic from filter_options API |
| Task Type | Dropdown | Dynamic from filter_options API |

### API Endpoints
```
GET .../statistic/analytics                        — Summary statistics
GET .../statistic/analytics/filter_options          — Available tags & task types
GET .../statistic/analytics/agent_activity          — Agent activity time series
GET .../statistic/analytics/session_source_breakdown — Source distribution
GET .../statistic/analytics/session_duration_distribution — Duration histogram
GET .../statistic/analytics/cost_token_usage        — Cost & token time series
GET .../statistic/workflow_costs                    — Workflow cost analytics
```

---

## 14. Project Overview Dashboard

### Feature: `features/project-overview/`
**Tab:** `overview` within Project Page

Dashboard with 4 stat sections:

| Section | Data | Visualization |
|---------|------|---------------|
| Platform Summary | Sessions count, total spend, workflow runs, board tasks | 4 stat cards |
| Board Task Distribution | Tasks per column | Stacked progress bar |
| Workflow Run Stats | Completed / In progress / Failed / Queued | 4 progress bars |
| Recent Activity | Paginated activity feed | Color-coded feed with relative timestamps |

**Polling:** 60-second auto-refresh interval.

### API Endpoints
```
GET .../statistic/overview                    — Platform summary
GET .../statistic/board_task_distribution     — Task distribution
GET .../statistic/workflow_runs               — Workflow run stats
GET .../statistic/recent_activity             — Recent activity feed
```

---

## 15. Agents Management

### Feature: `features/agents-management/`
**Routes:** `/company/agents` (company) + `agents` tab in project

**Dual scope:** All resource management features support both company-level and project-level CRUD.

### Agents Table
| Column | Content |
|--------|---------|
| Name | Agent name |
| Title | Agent title/role |
| Icon | Emoji icon |
| Source | Custom / BMAD Import badge |
| Scope | Company / Project badge |
| Actions | Edit, Delete |

### Create/Edit Agent Dialog
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Unique identifier |
| Title | Text | Display title |
| Icon | Emoji picker | Agent icon |
| Persona | Multi-line text | Agent personality/background |
| Communication Style | Multi-line text | How the agent communicates |
| Principles | Multi-line text | Guiding principles |

### API Endpoints
```
GET/POST           .../company/agents       — Company-level list/create
PATCH/DELETE        .../company/agents/:id   — Company-level update/delete
GET/POST           .../projects/:id/agents   — Project-level list/create
PATCH/DELETE        .../projects/:pid/agents/:id — Project-level update/delete
```

---

## 16. Tools Management

### Feature: `features/tools-management/`
**Routes:** `/company/tools` (company) + `tools` tab in project

### Tools Table
| Column | Content |
|--------|---------|
| Name | Tool name |
| Display Name | Human-readable name |
| Kind | Custom / System / Internal / Workflow badge |
| Scope | System / Company / Project badge |
| Docker Image | Container image |
| Enabled | Toggle |
| Actions | Edit, Delete |

### Create/Edit Tool Dialog
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Unique identifier |
| Display Name | Text | Human-readable name |
| Description | Multi-line text | Tool description |
| Docker Image | Text | Container image reference |
| Command | Text | Execution command |
| Required Config Items | Multi-select | Config items needed to run |
| Input Schema | JSON editor | JSON Schema for input validation |
| Tool Files | File editor | Multi-file editor (path, content, binary flag) |

### Tool Files Editor
- Add/remove files
- Per file: file path input, content text area, binary toggle
- Supports multipart upload

### API Endpoints
```
GET/POST           .../company/tools        — Company-level CRUD
PATCH/DELETE        .../company/tools/:id
GET/POST           .../projects/:id/tools    — Project-level CRUD
PATCH/DELETE        .../projects/:pid/tools/:id
```

---

## 17. Skills Management

### Feature: `features/skills-management/`
**Routes:** `/company/skills` (company) + `skills` tab in project

### Skills Table
| Column | Content |
|--------|---------|
| Name | Skill name |
| Title | Skill title |
| Kind | Internal / Custom badge |
| Scope | Company / Project badge |
| Description | Brief description |
| Actions | Edit, Delete (not for internal skills) |

### Create/Edit Skill Dialog
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Unique identifier |
| Title | Text | Display title |
| Content | Multi-line text | Skill content (markdown/text) |
| Description | Text | Brief description |

### API Endpoints
```
GET/POST           .../company/skills       — Company-level CRUD
PATCH/DELETE        .../company/skills/:id
GET/POST           .../projects/:id/skills   — Project-level CRUD
PATCH/DELETE        .../projects/:pid/skills/:id
```

---

## 18. MCP Servers Management

### Feature: `features/mcp-servers-management/`
**Routes:** `/company/mcp-servers` (company) + `mcp-servers` tab in project

### MCP Servers Table
| Column | Content |
|--------|---------|
| Name | Server name |
| Display Name | Human-readable name |
| Transport | HTTP / SSE / Stdio badge |
| Scope | Internal / Company / Project badge |
| URL/Command | Connection details |
| Enabled | Status indicator |
| Actions | Edit, Delete |

### Create/Edit MCP Server Dialog
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Unique identifier |
| Display Name | Text | Human-readable name |
| Transport | Dropdown | HTTP / SSE / Stdio |
| URL | Text | Server URL (for HTTP/SSE) |
| Command | Text | Shell command (for Stdio) |
| Headers | Key-value pairs | HTTP headers (for HTTP/SSE) |
| Environment Variables | Key-value pairs | Environment variables (for Stdio) |
| Description | Multi-line text | Server description |
| Enabled | Toggle | Enable/disable server |

**Config Item References:** Values can reference config items (secrets) using `ConfigItemValueField` component.

### API Endpoints
```
GET/POST           .../company/mcp_servers    — Company-level CRUD
PATCH/DELETE        .../company/mcp_servers/:id
GET/POST           .../projects/:id/mcp_servers — Project-level CRUD
PATCH/DELETE        .../projects/:pid/mcp_servers/:id
```

---

## 19. Config Items (Secrets & Variables)

### Feature: `features/config-items-management/`
**Routes:** `/company/config_items` (company) + `config` tab in project

### Config Items Table
| Column | Content |
|--------|---------|
| Name | Config item name |
| Type | Secret / Variable badge |
| Value | Displayed for variables, masked ("••••••••") for secrets |
| Scope | Company / Project badge |
| Description | Brief description |
| Actions | Edit, Delete |

### Filters
- Search text field (debounced)
- Type dropdown: All / Secret / Variable

### Create/Edit Dialog
| Field | Type | Description |
|-------|------|-------------|
| Name | Text | Unique identifier |
| Value | Text (or password for secrets) | The value |
| Description | Text | Purpose description |
| Type | Radio | Secret / Variable |

### API Endpoints
```
GET/POST           .../company/config_items     — Company-level CRUD
PATCH/DELETE        .../company/config_items/:id
GET/POST           .../projects/:id/config_items — Project-level CRUD
PATCH/DELETE        .../projects/:pid/config_items/:id
```

---

## 20. Integrations Management

### Feature: `features/integrations-management/`
**Routes:** `/company/integrations` (company) + `integrations` tab in project

### Integrations Panel
Lists connected integrations (GitHub, GitLab, Linear) with:
- Provider icon and name
- Status chip (active/inactive/error)
- Connected by (user name)
- GitHub URL (for GitHub integrations)
- Scope indicator

### Actions
| Action | Description |
|--------|-------------|
| Connect GitHub | Via GitHub App installation ID |
| Connect GitLab | Via personal access token |
| Delete integration | Remove connection |

### API Endpoints
```
POST   .../company/integrations/github_setup  — Setup GitHub integration
GET    .../company/integrations               — List integrations
POST   .../company/integrations               — Create integration
DELETE .../company/integrations/:id           — Delete integration
GET    .../projects/:id/integrations          — Project-level list
POST   .../projects/:id/integrations          — Project-level create
DELETE .../projects/:pid/integrations/:id     — Project-level delete
```

---

## 21. Repositories Management

### Feature: `features/repositories-management/`
**Routes:** `/company/repositories` (company) + `repositories` tab in project

### Repositories Panel
Table with: repository full name, source branch, clone URL, private badge, purpose, integration name.

### Add Repository Dialog
1. Select integration (dropdown of connected GitHub/GitLab integrations)
2. Select repository (dropdown, fetched from integration API)
3. Select branch (dropdown, fetched per repo)
4. Set purpose (text field)

### Edit Repository Dialog
- Change branch
- Update purpose

### API Endpoints
```
GET    .../repositories                     — List repositories
GET    .../repositories/available            — Available repos from integrations
GET    .../repositories/branches             — Branches for a specific repo
POST   .../repositories                     — Connect repository
PATCH  .../repositories/:id                 — Update repository
DELETE .../repositories/:id                 — Disconnect repository
```

---

## 22. Assets Management

### Feature: `features/assets-management/` + `features/asset-preview/`
**Routes:** `/company/assets` (company) + `assets` tab in project

### Assets Table
| Column | Content |
|--------|---------|
| Name | File name (monospace) |
| Folder | Folder path |
| Tags | Tag chips |
| Scope | Company / Project badge |
| Type | Document / Code / Image / Data / Other (auto-detected) |
| Size | Human-readable file size |
| Versions | Version count |
| Public | Public/Private badge |
| Created | Relative timestamp |
| Actions | Preview, Edit, Delete, Restore (if soft-deleted) |

### Upload Asset Dialog
- File picker (drag & drop or click)
- Name field (auto-populated from file name)
- Folder field (optional path)
- Tags (multi-input)
- Public toggle

### Edit Asset Dialog
- Name, folder, tags, public toggle

### Asset Preview
Multi-format inline previewer:
| Content Type | Renderer |
|-------------|----------|
| Markdown (.md) | `react-markdown` with `remark-gfm`, toggle raw/preview |
| Code/Text | Monospace pre-formatted display |
| Images | `<img>` element |
| Binary files | Download prompt |

Header shows: file extension badge, size, created date.

### Version History
- Lists all versions with: version number, size, created date, "Current" badge
- Restore to previous version

### API Endpoints
```
GET    .../assets                           — List assets
POST   .../assets                           — Upload new asset (multipart)
PATCH  .../assets/:id                       — Update metadata
DELETE .../assets/:id                       — Soft-delete asset
POST   .../assets/:id/restore              — Restore deleted asset
GET    .../assets/:id/versions              — Version history
GET    .../assets/:id/download              — Download asset file
```

---

## 23. Company Members

### Page: `pages/company-members/`
**Route:** `/company/members`

### Members Table
| Column | Content |
|--------|---------|
| User | Name + email |
| Role | Admin / Employee chip |
| Status | Active / Pending / Archived chip |
| Invited | Date + invited by |
| Actions | Context menu |

### Filters
| Filter | Type | Options |
|--------|------|---------|
| Search | Text (debounced 300ms) | Name/email |
| Role | Dropdown | All / Admin / Employee |
| Status | Dropdown | All / Active / Pending / Archived |

### Pagination
10 / 25 / 50 per page with server-side filtering (Ransack)

### Context Menu Actions
| Action | Description |
|--------|-------------|
| Archive user | Deactivate user account |
| Activate user | Reactivate archived user |
| Make Admin | Promote to admin role |
| Make Employee | Demote to employee role |
| Delete user | Permanent removal (confirmation dialog) |

**Protections:** Cannot demote last admin.

### Invite User Dialog
| Field | Type | Validation |
|-------|------|------------|
| Email | Text | Required, email format |
| Name | Text | Required |
| Role | Dropdown | Admin / Employee |

### API Endpoints
```
GET    /api/v1/company/users                — List users (with Ransack filters)
POST   /api/v1/company/users                — Invite user
PATCH  /api/v1/company/users/:id            — Update role/state
DELETE /api/v1/company/users/:id            — Delete user
```

---

## 24. User Profile

### Page: `pages/profile/`
**Route:** `/profile`

### Profile Form
| Field | Type | Editable |
|-------|------|----------|
| Email | Text | Read-only |
| Display Name | Text | ✓ |
| Preferred Agent Language | Dropdown (11 languages) | ✓ |
| Company | Text | Read-only |
| Role | Badge | Read-only |

### Default Agent Selector
Dropdown to choose default agent credential for new sessions.

### Default Model Selector
Per-credential model selector:
- Shows all configured agent credentials
- Autocomplete dropdown of available models (lazy-loaded per agent type)
- Set default model per agent credential

### Agent Credentials Section
See [Agent Credentials & Authentication](#25-agent-credentials--authentication).

### API Endpoints
```
GET   /api/v1/current_user               — User profile + credentials
PATCH /api/v1/current_user               — Update profile
GET   /api/v1/agent_models               — List available models
PUT   /api/v1/agent_models/update_default — Set default model
```

---

## 25. Agent Credentials & Authentication

### Feature: `features/agent-credentials/` + `features/agent-auth/`

### Credentials Section (on Profile page)
Lists all available agent runtimes with authentication status:

| Runtime | Status | Actions |
|---------|--------|---------|
| Claude Code | Configured ✓ / Not configured ✗ | Authenticate / Re-authenticate |
| Cursor CLI | Configured ✓ / Not configured ✗ | Authenticate / Re-authenticate |
| Codex | Configured ✓ / Not configured ✗ | Authenticate / Re-authenticate |
| Gemini CLI | Configured ✓ / Not configured ✗ | Authenticate / Re-authenticate |

Per credential metadata: created date, last used date, expires date.

### Agent Authentication Flow
1. Open full-screen dialog with `AgentAuthTerminal`
2. Optional: fill environment fields (for agents needing pre-config)
3. Start terminal session (`POST /api/v1/terminal_sessions` with `session_type: auth_setup`)
4. User completes authentication in embedded terminal
5. System polls `{traefikHttpBase}/t/{routeToken}/fs/auth` every 2 seconds for auth status
6. On detection: save credentials, poll `refetch()` every 500ms (max 20 attempts) for backend confirmation
7. Show "Authentication Complete" state

---

## 26. Shared UI Components

### `shared/ui/` — Reusable MUI Components

| Component | File | Description |
|-----------|------|-------------|
| `Loader` | `Loader/Loader.tsx` | Full-viewport centered `CircularProgress` |
| `Logo` | `Logo/Logo.tsx` | App logo with size/variant/colorScheme props |
| `RoutePendingIndicator` | `RoutePendingIndicator.tsx` | Top `LinearProgress` during route transitions |
| `StatusBar` | `StatusBar/StatusBar.tsx` | Bottom bar: session status, agent, cost, duration, user |
| `Terminal` | `Terminal/Terminal.tsx` | xterm.js terminal with fit + web-links addons; imperative API (`write`, `clear`) |
| `useTerminal` | `Terminal/useTerminal.ts` | Hook wrapping Terminal ref with helpers |
| `WorkflowStepper` | `WorkflowStepper/WorkflowStepper.tsx` | Collapsible workflow step display with status, costs, assets |
| `EmojiPicker` | `EmojiPicker/EmojiPicker.tsx` | MUI popover + `@emoji-mart` picker for single emoji selection |

---

## 27. State Management & API Layer

### Redux Store (`shared/api/store.ts`)
- Single Redux store with only `baseApi` reducer + middleware
- No custom slices — all server state via RTK Query
- Only client-side state: `localStorage` (selected project, sidebar collapsed)

### Base API (`shared/api/baseApi.ts`)
- Axios-based base query with:
  - CSRF token from meta tag
  - Automatic `camelCase` ↔ `snake_case` key conversion
  - 401 → redirect to `/login`
- Tag types: `CurrentUser`, `Project`, `Workflow`, `WorkflowStep`, `WorkflowRun`, `Agent`, `Tool`, `Skill`, `McpServers`, `ConfigItem`, `Integration`, `Repository`, `Asset`, `TerminalSession`, `BoardTask`, `BoardActivity`, `SessionArtifact`, `CompanyUser`

### API Modules (RTK Query `injectEndpoints`)
| Module | Location | Tags |
|--------|----------|------|
| Current User | `shared/api/` | `CurrentUser` |
| Agent Models | `shared/api/` | `AgentModels` |
| Terminal Sessions | `shared/api/` | `TerminalSession` |
| Config Items (select) | `shared/api/` | `ConfigItem` |
| Projects | `entities/project/` | `Project` |
| Board | `features/board-management/` | `BoardTask`, `BoardActivity` |
| Workflows | `features/workflows/` | `Workflow` |
| Workflow Steps | `features/workflow-steps/` | `WorkflowStep` |
| Workflow Runs | `features/workflow-execution/` | `WorkflowRun` |
| Workflow Cost Analytics | `features/cost-analytics/` | — |
| Project Analytics | `features/project-analytics/` | — |
| Project Overview | `features/project-overview/` | — |
| Agents | `features/agents-management/` | `Agent` |
| Tools | `features/tools-management/` | `Tool` |
| Skills | `features/skills-management/` | `Skill` |
| MCP Servers | `entities/mcp-server/` | `McpServers` |
| Config Items | `features/config-items-management/` | `ConfigItem` |
| Integrations | `features/integrations-management/` | `Integration` |
| Repositories | `features/repositories-management/` | `Repository` |
| Assets | `features/assets-management/` | `Asset` |
| Company Users | page-level | `CompanyUser` |
| Aixle Builder | `features/aixle-builder/` | — |

### Generated Routes (`shared/api/routes.ts`)
Generated by `ts_routes-rails` — TypeScript path helpers matching all Rails routes. Used as `Routes.backend.*()`.

### Frontend Routes (`shared/routes.ts`)
Manual path helpers for SPA routes. Used as `Routes.frontend.*`.

---

## 28. Real-Time Features (WebSockets)

All real-time communication uses **Action Cable** (Rails) with the consumer from `shared/lib/actionCableConsumer.ts`.

### Channels

| Channel | Hook | Trigger | Events |
|---------|------|---------|--------|
| `BoardChannel` | `useBoardChannel` | Board ID | `board_task.created`, `board_task.updated`, `board_task.destroyed`, `board_activity.created` |
| `WorkflowRunChannel` | `useWorkflowRunChannel` | Run ID | State change events → triggers refetch |
| `TerminalSessionChannel` | `useMetaActivityChannel` | Session ID | `meta_activity` (entity creation during Aixle builder) |
| `TerminalSessionChannel` | `useAiEngineEvents` | Session ID | AI engine events (used for live session monitoring) |

### Polling-Based Updates (not WebSocket)
| Feature | Interval | Purpose |
|---------|----------|---------|
| Session History | 15s | Refresh sessions list |
| Workflow Runs Widget | 10s | Refresh runs list |
| Project Overview | 60s | Refresh dashboard stats |
| Auth detection | 2s | Poll auth endpoint during agent setup |
| Credential save | 500ms (max 20) | Wait for Temporal workflow completion |
| Aixle Builder (run mode) | 5s | Poll workflow run state |

---

## 29. Routing & Navigation

### Complete Route Map

```
/ ...................... Redirect → last project or /company/projects
/login ................. Login page (unauthenticated)
/onboarding ............ 4-step onboarding wizard

/company/projects .............. Projects list
/company/projects/:id .......... Redirect → .../overview
/company/projects/:id/:tab ..... Project page (16 tabs)
    ?assigneeId=&taskType=&priority=&tags=&search=&task=  (board filters)

/company/projects/:id/sessions/new ........... New session (project-scoped)
/company/projects/:id/sessions/:sid .......... View session (project-scoped)
/company/projects/:id/sessions/:sid/artifacts  Session artifacts (project-scoped)

/company/projects/:id/workflow-runs/:rid ..... Workflow run detail
/company/projects/:id/workflows/:wid/builder . Workflow builder (project-level)
/company/projects/:id/aixle-builder .......... Aixle builder landing
/company/projects/:id/aixle-builder/:rid ..... Aixle builder session

/company/workflows/:wid/builder .............. Workflow builder (company-level)

/company/members ........... Company members management
/company/config_items ...... Config items (company-level)
/company/agents ............ Agents (company-level)
/company/tools ............. Tools (company-level)
/company/mcp-servers ....... MCP servers (company-level)
/company/skills ............ Skills (company-level)
/company/assets ............ Assets (company-level)
/company/integrations ...... Integrations (company-level)
/company/workflows ......... Workflows (company-level)
/company/repositories ...... Repositories (company-level)
/company/settings .......... Settings (placeholder — "Coming Soon")
/company/branding .......... Branding (placeholder — "Coming Soon")

/company/sessions ............ Sessions list (company-level)
/company/sessions/new ........ New session (company-level)
/company/sessions/:sid ....... View session (company-level)
/company/sessions/:sid/artifacts Session artifacts (company-level)

/profile ................... User profile + credentials
```

### Navigation Guards
| Guard | Condition | Action |
|-------|-----------|--------|
| Auth required | No authenticated user | → `/login` |
| Onboarding required | User not onboarded | → `/onboarding` |
| Onboarding done | Onboarded user on onboarding page | → `/company/projects` |
| Project default tab | `/company/projects/:id` without tab | → `.../overview` |
| Index redirect | `/` | → last project from localStorage or `/company/projects` |

---

## 30. Data Models Reference

### Core Entities

| Entity | Key Fields |
|--------|------------|
| **User** | id, email, name, role (employee/admin/super_admin), state (active/pending/suspended/archived), position, preferredAgentLanguage, onboardingState |
| **Company** | id, name, emailDomain, logoUrl, primaryColor, secondaryColor |
| **Project** | id, name, description, slug, state (active/paused/archived), ownerId, collaboratorsCount, lastActivityAt |
| **Board** | id, name, presetOrigin, boardColumns[] |
| **BoardColumn** | id, name, position, purpose, workflowBinding (workflowId, triggerMode, cooldownSeconds) |
| **BoardTask** | id, title, description, taskType (epic/story/bug), priority (critical/high/medium/low), assigneeId, boardColumnId, position, tags[], childrenCount, commentsCount, assetsCount, recentWorkflowRuns[], pendingWaits[] |
| **Workflow** | id, name, description, scopeType, stepsCount, lastRunAt, lastRunStatus, hasActiveRuns, baseToolIds, baseSkillIds, baseMcpServerIds, baseAssetIds, inheritAllProjectResources |
| **Step** | id, name, instructions, agentId, position, requiredAgentRuntime, preferredModel, allowNonInteractive, skipPolicy, onFailure, maxRetries, toolIds, mcpServerIds, skillIds, mountRepositories, bmadEnabled, dependsOnStepIds, subSteps[], inputAssetSpecs[], outputAssetSpecs[] |
| **WorkflowRun** | id, state (pending/running/paused/completed/failed/cancelled), mode (interactive/non_interactive/mixed), steps[], startedAt, completedAt, totalCost, totalTokens |
| **Agent** | id, name, title, icon, persona, communicationStyle, principles, source (custom/bmad_import), scopeIndicator |
| **Tool** | id, name, displayName, kind (custom/system/internal/workflow), dockerImage, command, requiredConfigItems, inputSchema, enabled, toolFiles[] |
| **Skill** | id, name, title, content, description, kind (internal/custom), scopeIndicator |
| **McpServer** | id, name, displayName, transport (http/sse/stdio), url, command, headers, env, description, enabled, kind (internal/custom), scopeIndicator |
| **ConfigItem** | id, name, value, description, itemType (secret/variable), scopeIndicator |
| **Integration** | id, provider (github/gitlab/linear), status (active/inactive/error), settings, connectedBy, githubUrl, scope |
| **Repository** | id, fullName, sourceBranch, cloneUrl, isPrivate, purpose, integration |
| **Asset** | id, name, folder, tags[], public, latestVersion, versionsCount, deletedAt, scopeIndicator |
| **TerminalSession** | id, sessionType (auth_setup/agent_session/tool_setup/workflow_step), agentType, state (not_started/running/ready/finished/failed), mode (interactive/non_interactive), projectId, containerId, routeToken, websocketUrl, ideUrl, initialPrompt, sessionConfig (bmad, configFiles, envVars), usage (tokens, cost), models[], pendingArtifactsCount |
| **AgentCredential** | id, agentType, configKeys, defaultModel, lastUsedAt, expiresAt |

### Enumerations

| Enum | Values |
|------|--------|
| AgentType | `claude_code`, `cursor_cli`, `codex`, `gemini_cli` |
| UserRole | `employee`, `admin`, `super_admin` |
| UserState | `active`, `pending`, `suspended`, `archived` |
| UserPosition | `qa`, `pm_po_ba`, `dev`, `designer`, `cto` |
| OnboardingState | `step1`, `step2`, `step3`, `step4`, `completed` |
| TaskType | `epic`, `story`, `bug`, `not_specified` |
| Priority | `critical`, `high`, `medium`, `low` |
| SessionType | `auth_setup`, `agent_session`, `tool_setup`, `workflow_step` |
| SessionState | `not_started`, `running`, `ready`, `finished`, `failed` |
| SessionMode | `interactive`, `non_interactive` |
| WorkflowRunState | `pending`, `running`, `paused`, `completed`, `failed`, `cancelled` |
| StepRunState | `pending`, `running`, `waiting_input`, `completed`, `failed`, `skipped` |
| McpTransport | `http`, `sse`, `stdio` |
| AnalyticsScope | `user`, `project` |
| AnalyticsPeriod | `7d`, `30d`, `90d`, `1y` |

### Color Mappings

| Domain | Colors |
|--------|--------|
| Task Type | Epic=purple, Story=blue, Bug=red, Not specified=gray |
| Priority | Critical=red, High=orange, Medium=yellow, Low=green |
| Agent Type | Claude Code=red, Cursor CLI=blue, Codex=green, Gemini CLI=purple |
| Workflow Run State | Completed=green, Running=blue, Paused=yellow, Failed=red, Cancelled=gray, Pending=gray |
| Step Run State | Completed=green, Running=blue (pulse), Waiting=yellow, Failed=red, Skipped=gray, Pending=gray |

---

## Appendix A: Complete Backend API Surface

### Authentication & User
```
POST   /api/v1/sessions                    — Login (email + password)
DELETE /api/v1/sessions                    — Logout
GET    /api/v1/auth/:provider              — OAuth redirect (HTML)
GET    /api/v1/auth/:provider/callback     — OAuth callback (HTML)
GET    /api/v1/current_user                — Current user profile
PATCH  /api/v1/current_user                — Update profile
GET    /api/v1/agent_models                — Available LLM models
PUT    /api/v1/agent_models/update_default — Set default model
POST   /api/v1/contact_requests            — Contact form
```

### Global Resources
```
POST   /api/v1/assets/presign              — Presign upload URL
POST   /api/v1/assets/upload               — Direct upload
CRUD   /api/v1/terminal_sessions           — Global terminal sessions
POST   /api/v1/terminal_sessions/:id/finish — Finish session
```

### Company Resources
```
CRUD   /api/v1/company/users               — User management
CRUD   /api/v1/company/config_items        — Config items
CRUD   /api/v1/company/agents              — Agents
CRUD   /api/v1/company/tools               — Tools
CRUD   /api/v1/company/mcp_servers         — MCP servers
CRUD   /api/v1/company/skills              — Skills
CRUD   /api/v1/company/workflows           — Workflows (+ nested steps)
CRUD   /api/v1/company/repositories        — Repositories (+ available, branches)
CRUD   /api/v1/company/assets              — Assets (+ download, versions, restore)
CRUD   /api/v1/company/integrations        — Integrations (+ github_setup)
GET    /api/v1/company/terminal_sessions   — Company sessions
GET    /api/v1/company/terminal_sessions/:id/artifacts — Session artifacts
```

### Project Resources (under `/api/v1/company/projects/:project_id/`)
```
CRUD   collaborators                       — Project members
CRUD   config_items, agents, tools, mcp_servers, skills
CRUD   workflows (+ duplicate, nested steps)
CRUD   repositories (+ available, branches)
CRUD   assets (+ download, versions, restore)
CRUD   integrations
CRUD   terminal_sessions
POST   aixle_builder/start, GET status     — Aixle builder
```

### Board (under `.../projects/:id/`)
```
CRUD   board                               — Board management (+ presets)
CRUD   board/columns (+ reorder, workflow_binding)
CRUD   board/tasks (+ move, trigger_workflow, workflow_runs)
CRUD   board/tasks/:id/comments
CRUD   board/tasks/:id/assets
DELETE board/tasks/:id/waits/:id
GET    board/tasks/:id/transitions, activities, statistics
GET    board/activities
CRUD   board/view_presets
```

### Analytics & Statistics (under `.../projects/:id/statistic/`)
```
GET    analytics (+ filter_options, agent_activity, session_source_breakdown, session_duration_distribution, cost_token_usage)
GET    workflow_costs
GET    overview
GET    recent_activity
GET    workflow_runs
GET    board_task_distribution
```

### Workflow Runs (under `.../projects/:id/`)
```
GET/POST  workflow_runs
GET       workflow_runs/:id
POST      workflow_runs/:id/approve_step
POST      workflow_runs/:id/retry_step
POST      workflow_runs/:id/skip_step
POST      workflow_runs/:id/cancel
GET       workflow_runs/:id/workflow_run_assets
POST      workflow_run_assets/:id/export
POST      workflow_run_assets/export_all
GET       workflow_run_assets/:id/download
```

---

## Appendix B: Feature Complexity Ranking

| # | Feature | Complexity | Components | API Endpoints | Real-Time |
|---|---------|-----------|------------|---------------|-----------|
| 1 | Board Management | **Very High** | ~15 components | ~20 endpoints | Action Cable |
| 2 | Workflow Builder | **Very High** | ~8 components | ~15 endpoints | — |
| 3 | Workflow Runs | **High** | ~5 components | ~10 endpoints | Action Cable |
| 4 | Terminal Sessions | **High** | ~5 widgets | ~8 endpoints | Polling + iframes |
| 5 | Aixle Builder | **High** | ~5 components | ~3 endpoints | Action Cable |
| 6 | Analytics | **Medium-High** | ~3 components | ~7 endpoints | — |
| 7 | Assets Management | **Medium** | ~8 components | ~7 endpoints | — |
| 8 | Onboarding | **Medium** | ~1 page | ~3 endpoints | Polling |
| 9 | Tools Management | **Medium** | ~6 components | ~4 endpoints | — |
| 10 | Company Members | **Medium** | ~3 components | ~4 endpoints | — |
| 11 | Agents Management | **Low-Medium** | ~5 components | ~4 endpoints | — |
| 12 | MCP Servers | **Low-Medium** | ~5 components | ~4 endpoints | — |
| 13 | Skills Management | **Low** | ~5 components | ~4 endpoints | — |
| 14 | Config Items | **Low** | ~5 components | ~4 endpoints | — |
| 15 | Repositories | **Low** | ~3 components | ~6 endpoints | — |
| 16 | Integrations | **Low** | ~1 component | ~4 endpoints | — |
| 17 | Profile | **Low** | ~3 components | ~3 endpoints | — |
| 18 | Projects List | **Low** | ~2 components | ~2 endpoints | — |
| 19 | Login | **Low** | ~2 components | ~2 endpoints | — |
| 20 | Session Artifacts | **Low** | ~1 page | ~3 endpoints | — |

---

## Appendix C: Placeholder / Incomplete Features

| Feature | Route | Status |
|---------|-------|--------|
| Company Settings | `/company/settings` | "Coming Soon" placeholder |
| Company Branding | `/company/branding` | "Coming Soon" placeholder |
| Linear Integration | — | Provider listed but no connect UI |
