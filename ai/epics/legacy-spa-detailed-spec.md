# Legacy SPA — Detailed Component & Interaction Specification

> **Purpose:** Pixel-level documentation of every UI element, interaction, conditional render, state, validation rule, and behavior in the original SPA frontend. Written as a rewrite specification — if you implement everything described here, you have full feature parity.
>
> **Created:** 2026-04-03  
> **Companion:** `legacy-spa-functionality-audit.md` (high-level overview)  
> **Stack:** React 18, TanStack Router, MUI v5, RTK Query, notistack, Recharts, xterm.js, DnD Kit

---

## Table of Contents

- [1. Application Shell](#1-application-shell)
- [2. Login](#2-login)
- [3. Onboarding (4-step wizard)](#3-onboarding)
- [4. Projects List](#4-projects-list)
- [5. Project Page (tabbed)](#5-project-page)
- [6. Board (Kanban)](#6-board)
- [7. Workflows](#7-workflows)
- [8. Workflow Builder](#8-workflow-builder)
- [9. Workflow Runs](#9-workflow-runs)
- [10. Run Workflow Modal](#10-run-workflow-modal)
- [11. Aixle Builder](#11-aixle-builder)
- [12. Terminal Sessions](#12-terminal-sessions)
- [13. Session Artifacts](#13-session-artifacts)
- [14. Project Overview Dashboard](#14-project-overview-dashboard)
- [15. Project Analytics](#15-project-analytics)
- [16. Agents Management](#16-agents-management)
- [17. Tools Management](#17-tools-management)
- [18. Skills Management](#18-skills-management)
- [19. MCP Servers Management](#19-mcp-servers-management)
- [20. Config Items](#20-config-items)
- [21. Integrations](#21-integrations)
- [22. Repositories](#22-repositories)
- [23. Assets Management](#23-assets-management)
- [24. Company Members](#24-company-members)
- [25. User Profile](#25-user-profile)
- [26. Agent Credentials & Auth](#26-agent-credentials)

---

## 1. Application Shell

### 1.1 Provider Stack
Outer → inner: `Sentry.ErrorBoundary` (shows dialog on crash) → Redux `Provider` → MUI `ThemeProvider` (dark theme + CssBaseline) → `SnackbarProvider` (max 3, top-right, 1500ms auto-hide) → `React.Suspense` (LinearProgress fallback) → TanStack `RouterProvider` (scroll restoration, preload on intent, 300ms pending delay).

### 1.2 Root Layout
Renders `<RoutePendingIndicator />` (thin top LinearProgress bar during route transitions) + `<Outlet />`.

### 1.3 Auth Layout
Wraps all routes except `/login`. Guards:
- No user + not loading → redirect `/login`
- User exists + onboarding not completed + not on `/onboarding` → redirect `/onboarding`
- User onboarded + on `/onboarding` → redirect `/company/projects`
- While checking: shows full-page `<Loader />` (centered CircularProgress)

Chrome structure (when `showChrome` = onboarding completed + not on onboarding page):
- Top: `<AppHeader />`
- Left: `<AppSidebar />`
- Center: `<main><Outlet /></main>`
- Bottom: footer "Powered by" + `<Logo width={60} />`

### 1.4 AppHeader (Top Navigation Bar)
**Left side:**
1. **Company logo** — if `company.logoUrl` exists, shows image; otherwise `BusinessIcon`. Clicking navigates to `/company/projects`.
2. **Project Selector** — button shows current project name (or "All Projects"), with `ArrowDropDown` icon. Opens menu with:
   - "All Projects" (highlighted when none selected) + divider
   - List of all projects. Clicking a project saves ID to `localStorage('selected-project-id')` and navigates to it.
3. **Vertical divider**
4. **Three dropdown menus** (each button has `ArrowDropDown`):
   - **"Work"** → Sessions, Workflows, Assets
   - **"Agent Context"** → Agents, Tools, MCP Servers, Skills (all `adminOnly`)
   - **"Settings"** → Integrations, Repositories, Secrets & Variables, Members (all `adminOnly`)
   - `adminOnly` items hidden when `currentUser.role !== 'admin'`
   - Button highlighted when active route matches any child path

**Right side:**
5. User name (13px) + Avatar (initials, 32px, primary color). Dropdown menu:
   - "My Profile" (PersonIcon) → navigates to `/profile`
   - Divider
   - "Sign Out" (LogoutIcon) → DELETE `/api/v1/sessions`, redirect to `/login`

### 1.5 AppSidebar (Left Navigation)
**Only rendered** on project routes (`/company/projects/:projectId/...`).

**Dimensions:** 220px expanded, 56px collapsed. Collapse state persisted in `localStorage('sidebar-collapsed')`.

**Toggle button** at bottom: `ChevronLeft` (collapse) / `ChevronRight` (expand).

**Collapsed mode:** Only shows icons with tooltips on hover.

**Navigation groups (3 divider-separated sections):**

| Group | Items (icon, label, tab slug) |
|-------|------|
| Primary | DashboardOutlined "Overview" `overview`, ViewKanbanOutlined "Tasks" `board`, TerminalOutlined "Sessions" `sessions`, AccountTreeOutlined "Workflows" `workflows`, PlaylistPlayOutlined "Runs" `workflow-runs`, InsertDriveFileOutlined "Assets" `assets`, TrendingUpOutlined "Analytics" `analytics` |
| Config | SourceOutlined "Repositories" `repositories`, LinkOutlined "Integrations" `integrations`, SmartToyOutlined "Agents" `agents`, BuildOutlined "Tools" `tools`, DnsOutlined "MCP Servers" `mcp-servers`, AutoAwesomeOutlined "Skills" `skills` |
| Admin | VpnKeyOutlined "Secrets & Variables" `config`, GroupOutlined "Members" `members`, SettingsOutlined "Settings" `settings` |

Each item links to `/company/projects/:projectId/:tab`. Active item is highlighted based on current route match.

---

## 2. Login

**Route:** `/login`

### Auto-redirect
If user already authenticated: redirect to `/company/projects` (if onboarded) or `/onboarding`.

### OAuth Error Handling
URL search param `?error=X` maps to snackbar messages:
- `pending_approval` → "Your account is pending approval..."
- `deactivated` → "Your account has been deactivated..."
- `oauth_failed` → "Failed to authenticate with Google..."
- `oauth_error` → "An error occurred during authentication..."
- default → "Authentication failed. Please try again."

Shows only once per mount (tracked via `errorShownRef`).

### UI Layout
Centered card (max-width 420px) with:
1. `<Logo width={120} colorScheme="dark" />`
2. **Google login button** — full-width outlined button with inline Google 4-color SVG logo + "Sign in with Google". Links to `/api/v1/auth/google` with full page reload.
3. **Divider** with text "OR"
4. **Subtitle**: "Enter your credentials to access your workspace"
5. **Email field** — label "Email", placeholder "you@company.com", `autoComplete="username"`
6. **Password field** — label "Password", type="password", placeholder "••••••••", `autoComplete="current-password"`
7. **Submit button** — "Sign in" / "Signing in...", contained, disabled when loading
8. **Footer**: "AI Agent Orchestration Platform"

### Validation (Zod)
- `email`: required + valid email format
- `password`: required

### Submit
POST `{ user: { email, password } }` to `/api/v1/sessions`. Success: snackbar "Welcome back!", `window.location.href = '/'`. Error: field-level errors via `setErrorsToForm` or snackbar "Invalid email or password".

---

## 3. Onboarding

**Route:** `/onboarding`

### Step Machine (backend AASM)
States: `step1`, `step2`, `step3`, `step4`, `completed`. Events: `go_next`, `go_previous`, `complete`.

### Progress Indicator
`LinearProgress` bar + 4 numbered circles (✓ for completed, highlighted for active). Labels: "Your Profile", "Select Agents", "Authenticate", "Complete".

### Welcome Section (always visible)
- Company logo (if exists)
- "Welcome to {companyName}! 🎉"
- "Let's set up your profile and AI agents to get started"
- Italic note: "This setup is required to start using the platform"

### Step 1: Your Profile
- Title: "Tell Us About Yourself"
- Subtitle: "Help us personalize your experience..."
- **Position** — required Select, placeholder "Select your position". Options: Developer, QA Engineer, Product Manager / BA, Designer, CTO.
- **Preferred Agent Language** — required Select, placeholder "Select your preferred language". Options: English, Russian, Spanish, German, French, Japanese, Chinese.
- Validation warning (after submit attempt): "⚠️ Please fill in all required fields to continue"
- **Button**: "Continue" / "Saving..." / "Loading..."
- Auto-saves on field change with 300ms debounce.

### Step 2: Select Agents
- Title: "Select AI Agents to Configure"
- Subtitle: "Select at least one AI coding agent..."
- **2×2 grid** of agent cards. Each card:
  - Checkbox (top-right corner)
  - Color bar matching agent color (claude_code=#d97706, cursor_cli=#7c3aed, codex=#10a37f, gemini_cli=#3b82f6)
  - Agent name + description
  - Click/keyboard toggles selection
  - Selected: blue-ish border + background tint
- Agents: Claude Code, Cursor CLI, OpenAI Codex, Gemini CLI
- Validation: "⚠️ Select at least one agent to continue"
- **Buttons**: "Back", "Continue" (disabled if none selected)
- Auto-saves selections on change (debounced 300ms).

### Step 3: Authenticate
- Title: "Authenticate Your Agents"
- Subtitle: "Sign in to at least one agent's service..."
- **Left panel** (280px): List of selected agents showing:
  - Color bar, name, status badge (✓ green for authenticated)
  - Status text: "Authenticated" / "Click to authenticate" / "Authenticating..." / "Saving credentials..." / "Authentication failed"
  - Counter: "{n}/{total} authenticated"
- **Right panel** (flex, min-height 700px):
  - Agent selected → `<AgentAuthTerminal>` component
  - No agent selected → 🔐 icon + "Select an agent to authenticate"
- **Credential save polling**: On auth complete → poll `refetch()` every 500ms, max 20 attempts (10 seconds), waiting for Temporal workflow to persist credentials.
- Validation: "⚠️ Authenticate at least one agent to continue"
- **Buttons**: "Back", "Continue ({n}/{total})" or "Continue"

### Step 4: Complete
- 🎉 icon
- "You're all set!"
- "Review your configuration and click 'Get Started' to begin."
- **Profile summary card**: position label + language label
- **Agent summary cards**: color bar, name, "✓ Authenticated" (green) or "⚠ Not authenticated" (orange)
- Validation: "⚠️ Please authenticate at least one agent to complete setup"
- **Buttons**: "Back", "Get Started" (disabled if transitioning or no authenticated agents)
- On complete: snackbar "Welcome! Your agents are configured and ready to use.", navigate to `/company/projects`

---

## 4. Projects List

**Route:** `/company/projects`

### Header
- Title: "Projects"
- **"Create Project"** button (contained, AddIcon)

### Search
TextField, placeholder "Search projects...", client-side filtering on `name` and `description`.

### Grid
Responsive 3-column grid of `ProjectCard` components. Each card:
- Name (18px bold)
- Description (2-line clamp, 52px min-height)
- Chip "{n} collaborator(s)" (only if active + collaborators > 0)
- Footer: collaborator count stat (20px monospace bold) + "Last activity {relativeTime}" (if `lastActivityAt` exists)
- Hover: blue border, translateY(-2px), shadow

### Empty States
- No projects: "No projects"
- No search results: "No matching projects"

### Create Project Dialog
- Title: "Create Project"
- Fields: Name (required), Description (optional)
- Buttons: Cancel, Create
- On success: navigate to new project, snackbar

---

## 5. Project Page

**Route:** `/company/projects/:projectId/:tab`  
**Default redirect:** `/company/projects/:projectId` → `…/overview`

### URL Search Params (Board tab)
`assigneeId`, `taskType`, `priority`, `tags` (comma-separated), `search`, `task` (number — deep-link to specific task)

### 16 Tabs
| Tab | Component | Source |
|-----|-----------|--------|
| `overview` | ProjectOverviewPanel | features/project-overview |
| `board` | BoardPanel | features/board-management |
| `workflows` | WorkflowsPanel + ConnectedRunModal | features/workflows + features/run-workflow |
| `workflow-runs` | WorkflowRunsWidget | widgets/workflow-runs |
| `assets` | AssetsPanel + AssetPreview | features/assets-management |
| `sessions` | SessionHistoryWidget + "New Session" button | widgets/session-history |
| `members` | MembersTab (inline) | — |
| `config` | ConfigItemsPanel | features/config-items-management |
| `agents` | AgentsPanel | features/agents-management |
| `tools` | ToolsPanel | features/tools-management |
| `mcp-servers` | McpServersPanel | features/mcp-servers-management |
| `skills` | SkillsPanel | features/skills-management |
| `repositories` | RepositoriesPanel | features/repositories-management |
| `integrations` | IntegrationsPanel | features/integrations-management |
| `settings` | SettingsTab (inline) | — |
| `analytics` | ProjectAnalyticsPanel | features/project-analytics |

### Inline MembersTab
- Lists project collaborators
- Add from company users (Autocomplete)
- Remove with confirmation. Only project owner can manage.

### Inline SettingsTab
- Edit project name + description, save button

---

## 6. Board (Kanban)

**The most complex feature. Full kanban board with DnD Kit drag-and-drop, filtering, task sidebar, comments, assets, activity, statistics, and workflow triggers.**

### 6.1 Board Panel — Main View

**State:**
- `filters` — persisted per board in `localStorage('board-${boardId}-filters')`, initialized from URL search params
- `collapsedColumns` — Set of column IDs, persisted in `localStorage('board-${boardId}-collapsed')`
- `settingsOpen`, `creatingInColumn`, `activeTask` (for DragOverlay)

**DnD Setup:** `@dnd-kit/core` with MouseSensor (distance: 8px) + TouchSensor (delay: 200ms, tolerance: 5px). Collision: `pointerWithin` first, fallback `closestCorners`.

**Header actions (right side):**
- **Collapse/Expand all** — IconButton. If all collapsed → `UnfoldMoreIcon` "Expand all columns". Otherwise → `UnfoldLessIcon` "Collapse all columns".
- **Board settings** — IconButton with `SettingsIcon`, tooltip "Board settings".

**Loading state:** 3 Skeleton boxes (300×400, rounded 10px).

**No board state:** Shows `CreateBoardView`:
- `DashboardCustomizeIcon` (64px, 50% opacity)
- "No task board yet"
- "Choose a template to get started. You can customize columns later."
- Preset cards (260px wide, outlined): each shows `displayName` + chips for column names
- Creating state: Alert "Creating board..."

**WebSocket:** Action Cable `BoardChannel` by `board_id`. Events:
- `board_task.created` → deferred board refetch
- `board_task.updated` → deferred board refetch
- `board_task.destroyed` → optimistic cache removal
- `board_activity.created` → invalidate Activity tag

**Deferred refetch:** During drag operations (`boardMoveMutationsInFlight > 0`), WebSocket-triggered refetches are postponed to avoid UI snapping.

### 6.2 Board Column

**Expanded view (280px wide):**
- **Header row:**
  - Collapse button: `ChevronLeftIcon` (16px), tooltip "Collapse column"
  - Column name: 13px bold uppercase, letter-spacing 0.5px. If column has `purpose`, name wrapped in Tooltip showing purpose text
  - Task count: 11px disabled color
  - Add button: `AddIcon`
- **Task list:** scrollable, SortableContext (vertical list). Empty: "No matching tasks" (if filtered) or "No tasks yet"
- **Drop highlight:** when `isOver` — primary.50 background, primary.main 2px outline

**Collapsed view (44px wide):**
- Droppable area. Click expands.
- `Badge badgeContent={tasks.length}` with `ChevronRightIcon`
- Column name in vertical writing mode (Tooltip on hover)
- Up to 10 task indicators as `CollapsedTaskIndicator`:
  - 34×8px rounded rectangle
  - Color: latest workflow run state color (green/blue/red/gray) or yellow (#eab308) for pending waits
  - Active workflow runs: `workflowPulse` animation (opacity 1→0.4, 1.5s infinite)
  - Hover: brightness(1.2)
  - Tooltip: task title + status + elapsed time

### 6.3 Task Card (Kanban Card)

Card with elevation=1, borderRadius 8px. Dragging: opacity 0.5.

**Layout:**
- **Title row:** priority dot (8×8px circle, colored) + title (13px, fontWeight 500) + workflow dots
  - Priority dot: only if `task.priority` truthy. Colors: critical=#d32f2f, high=#ed6c02, medium=#eab308, low=#2e7d32. Tooltip = priority name.
  - Workflow dots: shown if `pendingWaits.length > 0` OR `recentWorkflowRuns.length > 0`. Each run = 7×7px circle (color from `workflowStatusColor`), active states get pulse animation. Pending waits = yellow dots. Tooltip lists all runs and waits.
- **Meta row:** type chip (colored: epic=#9c27b0, story=#1976d2, bug=#d32f2f, not_specified=#9e9e9e) + up to 3 tag chips (outlined, 18px height, 10px font) + overflow chip "+N"
- **Footer:** assignee avatar (20×20px initials, Tooltip=name) + comments count (ChatBubbleOutlineIcon 12px + count)

### 6.4 Board Filter Bar

Horizontal flex row (gap 1, flex-wrap):
1. **Assignee** — Select (minWidth 130): "All" + project members
2. **Type** — Select (minWidth 130): "All types", Epic, Story, Bug, Not specified
3. **Priority** — Select (minWidth 130): "All priorities", Critical, High, Medium, Low
4. **Tags** — Autocomplete multiple freeSolo (minWidth 200): suggestions from `COMMENT_TAG_SUGGESTIONS`
5. **Search** — TextField (minWidth 180): placeholder "Search title...", SearchIcon adornment
6. **Presets** — `PresetSelector` button
7. **Clear** — shown only when any filter is active: "Clear" button with `ClearIcon`

### 6.5 View Presets

**Built-in presets:** "My Work" (filters to current user), "All Bugs" (filters to bug type).

**Preset menu:**
- "BUILT-IN" section + "SAVED" section (with delete buttons for own presets)
- "Save current filters" item with `SaveIcon` (disabled when no active filters)

**Save dialog:** Title "Save Filter Preset". Name field + "Share with team" Switch. Save disabled when name empty.

### 6.6 Task Sidebar (Drawer)

**Width:** 480px (or 50vw when expanded). Expand toggle: `ChevronLeftIcon` / `ChevronRightIcon`.

**Header:**
- Task type chip (colored)
- Inline editable title (click to edit, blur/Enter to save)
- **"Run workflow"** button — contained, `PlayArrowIcon`. **Shown only when:**
  - Column has `workflowBinding.triggerMode === 'manual'`
  - AND no active workflow run (pending/running/paused)
- Delete button — error IconButton with `DeleteIcon`, tooltip "Delete task"
- Close button

**5 Tabs:**

#### Tab: Details
| Section | UI | Details |
|---------|-------|---------|
| DESCRIPTION | Click-to-edit textarea (minRows 3) | "Click to add description..." placeholder. Saves on blur. |
| ASSIGNEE | Select | "Unassigned" + project members (name or email) |
| TYPE | Select | Not specified, Epic, Story, Bug |
| PRIORITY | Select | None, Low, Medium, High, Critical |
| PARENT EPIC | Select (only if type ≠ epic AND epics exist) | "None" + all epic tasks |
| TAGS | Autocomplete multiple freeSolo | "Add tag and press Enter" |
| WORKFLOW RUNS | List (only if runs exist) | State chip (colored), link to run page (opens new tab), timestamp |
| CHILD TASKS | List (only if type = epic) | "Add" button, each child shows type chip + clickable title |
| PENDING WAITS | List (only if waits exist) | HourglassEmptyIcon, wait type chip (warning), link to GitHub PR/Actions, delete button |

#### Tab: Comments (N)
- **Filters:** Author type Select (all/human/agent/system) + Tag TextField
- **Comment form:** multiline TextField (Cmd+Enter submits) + Tags Autocomplete (suggestions: feedback, tech_design, code_review, qa_report, implementation_notes) + "Send" button with `SendIcon`
- **Collapse/Expand all** button (shown if >1 comment)
- **Each comment:** Avatar (22px) + name + author type chip + timestamp. Collapsed: single-line preview. Expanded: markdown rendered (`react-markdown` + `remarkGfm`). Tags as chips below.

#### Tab: Assets (N)
- Upload button "Upload File" with `CloudUploadIcon` (hidden file input)
- Each asset: name, file size (B/KB/MB), content type, author type, tags. Download button (opens in new tab). Delete button.

#### Tab: Activity
- Paginated list (15 per page) of activity items. Each: `AccessTimeIcon` + description + relative time. "Load more" button.

#### Tab: Statistics (BarChartIcon)
- **3 stat cards:** Total Cost (`formatCostCents`), Total Tokens (`formatTokens`), Total Run Time (`formatDuration`)
- **Breakdown by Workflow** (if data): horizontal BarChart (recharts) + detail table (Workflow, Cost, Tokens, Run Time)
- **Waits** section (if data): "N pending · N resolved". Each wait: CheckCircleOutline (green, resolved) or HourglassEmpty (yellow, pending), wait type, duration.
- Loading: 3 skeleton stat cards + 1 skeleton rectangle.

### 6.7 Create Task Dialog
- Title: "Create Task"
- Fields: Title (required, autoFocus), Description (multiline minRows 3), Type + Priority (side by side selects), Column + Assignee (side by side selects), Parent Epic (conditional), Tags (freeSolo Autocomplete)
- If creating as child of epic: "Epic" type option filtered out, `parentTaskId` auto-set
- Buttons: Cancel, "Create" / "Creating..."

### 6.8 Board Settings Dialog
- Title: "Board Settings", maxWidth md
- Instruction: "Drag to reorder, rename, or remove columns. Assign workflows to auto-trigger when tasks enter a column."
- **Per column (draggable row):**
  - `DragIndicatorIcon` handle (native HTML drag)
  - **Name** — TextField, placeholder "Column name"
  - **Purpose** — TextField, placeholder "Purpose"
  - **Workflow** — Select: "None" + all project workflows
  - **Trigger mode chip** (shown when workflow assigned): Clickable chip showing `triggerMode`. Click toggles `auto` ↔ `manual`. Color: primary if auto, default if manual. Icon: `LinkIcon`.
  - **Unlink workflow** — `LinkOffIcon` IconButton, tooltip "Unlink workflow"
  - **Remove column** — red DeleteIcon IconButton, tooltip "Remove column"
- **"Add Column"** button with AddIcon
- Save is sequential: delete removed → create new → update dirty → reorder → update workflow bindings
- Buttons: Cancel, Save / "Saving..."

### 6.9 Activity Feed Panel (Bottom)
- Collapsible (260px max height, hidden by default)
- Header: "ACTIVITY FEED" (clickable to toggle) with ExpandLess/ExpandMore icon
- Content: activity items (20 per page) + "Load more". API query skips when panel closed.

### 6.10 Drag & Drop Behavior
- **Drag start:** Sets `activeTask` for DragOverlay (rendered semi-transparent outside any column)
- **Drag end:** Determines target column from drop zone (task or column droppable). Calls `moveTask` with computed position.
- **Optimistic update:** Immediately updates RTK cache (reorders positions in old/new columns), undoes on server error.
- **Global counter** `boardMoveMutationsInFlight`: while >0, WebSocket-triggered refetches are deferred.

---

## 7. Workflows

### Workflows Panel
- **Title:** "Project Workflows" / "Company Workflows"
- **Subtitle:**
  - Project: "Manage workflows for this project. Company workflows are shared across all projects."
  - Company: "Manage company-wide workflow templates available in all projects."
- **Buttons:** "Run History" (outlined, HistoryIcon — project only), "New Workflow" (contained, AddIcon)
- **AixleBuilderBanner** — shown in project context: gradient purple card with "Open Builder" button
- **Search:** placeholder "Search workflows...", debounced 300ms, filters on name and description

**Per workflow card (3-column grid):**
- Name (16px, 500) + "company" Chip (when inherited from company, primary outlined)
- Description excerpt (truncated)
- Meta: "{stepsCount} steps" + " · Last run {date}" (if exists)
- **Buttons:**
  - "Run" (contained, small, PlayArrowIcon) — project only
  - "Copy & Configure" (outlined, ContentCopyIcon) — when inherited from company
  - "Configure" (outlined, SettingsIcon) — when own workflow
  - Edit IconButton (EditIcon) — not for inherited
  - Delete IconButton (red DeleteIcon) — not for inherited

**Empty:** wrench emoji 🔧, "No workflows match your search" / "No workflows yet", "Create your first workflow" button

### Create Workflow Dialog
- Title: "New Workflow", maxWidth sm
- Fields: Name (placeholder "My Workflow", autoFocus), Description (placeholder "What this workflow does...", multiline minRows 3)
- Validation: name required max 200, description optional max 2000
- Buttons: Cancel, "Create" / "Creating..."

### Edit Workflow Dialog
- Title: "Edit Workflow"
- Warning Alert (if active runs): "Workflow has active runs. Changes will not affect them."
- Same fields as create, pre-populated
- Buttons: Cancel, "Save" / "Saving..."

### Delete Workflow Dialog
- Title: "Delete Workflow"
- If active runs: error Alert "Cannot delete workflow with active runs. Stop all runs first." + Delete button disabled
- Otherwise: 'Delete workflow "{name}"? This will remove all steps. Historical runs will be preserved.' (name bold)
- Buttons: Cancel, "Delete" / "Deleting..." (error)

---

## 8. Workflow Builder

**Routes:** `/company/workflows/:workflowId/builder` (company) or `/company/projects/:projectId/workflows/:workflowId/builder` (project)

### Layout
```
┌─────────────────────────────────────────────────────┐
│  [← Back]  Workflow Name (editable, 22px)  [Run ▶]  │
│            Description (editable, 13px,              │
│            placeholder "Add a description...")       │
│            Scope chip (company/project)              │
├─────────────────┬───────────────────────────────────┤
│  STEP SIDEBAR   │   DETAIL PANEL                    │
│  (ordered list) │   (selected step config           │
│                 │    or Base Resources accordion)    │
│  [+ Add Step]   │                                   │
└─────────────────┴───────────────────────────────────┘
```

### Read-only Mode
When viewing company workflow from project context: entire page gets info banner "This is a company-level workflow. Copy it to your project to customize." with "Copy & Configure" button (duplicates + navigates to builder).

### Auto-save
- All text fields: 500ms debounce via `useGuardedDraftSync` (prevents stale data overwriting in-flight edits)
- Toggle/dropdown changes: immediate save

### Step Sidebar (Left)
Ordered list of step cards, each showing:
- Position number
- Step name
- **Chips** (conditional):
  - `requiredAgentRuntime` set → warning Chip "Requires: {agentName}"
  - `allowNonInteractive` → Chip "Auto-run"
  - `bmadEnabled` → info Chip "BMAD"
  - No dependencies → outlined Chip "Root"
  - Has dependencies → secondary outlined Chip "after: {stepNames}" (maxWidth 180)
- Reorder arrows (up/down IconButtons, disabled at boundaries, `e.stopPropagation`)
- Click selects step for detail panel

**"+ Add Step"** button (not shown in read-only): creates step with name "Step {N}", position N.

### Base Resources Section (Accordion)
- Summary: "Base Resources" (15px bold) + "Available in all steps" (12px secondary)
- **"Inherit all project resources" switch** — when ON, disables all selectors below and shows: "All project tools, skills, and MCP servers are available in every step."
- **4 Autocomplete multi-selects** (all disabled when inheritAll or readOnly):
  - Base Tools (labels: `displayName || name`)
  - Base Skills (labels: `title || name`)
  - Base MCP Servers (labels: `displayName || name`)
  - Base Assets (labels: `folder/name` or `name`)

### Step Detail Panel
**Sections top to bottom:**

1. **Header:** "Step #{position}" + Delete IconButton (red, tooltip "Delete step")
2. **Name** — TextField, size small
3. **Description** — TextField, multiline minRows 2
4. **Instructions** — TextField, multiline minRows 8, placeholder "Enter step instructions... Use {{artifact_name}} for variable references."
5. **Agent** — Select, empty option "<em>No agent</em>", shows `agent.title || agent.name`. Immediate save.
6. **Required Agent Runtime** — Select, empty option "<em>None (use default)</em>", options from `AVAILABLE_AGENTS`. Immediate.
7. **Preferred Model** (shown only when runtime set) — Autocomplete, placeholder "Default (runtime selects)", loads models on open. Immediate.
8. **Divider**
9. **Auto-run switch** — "Auto-run available (skip user approval in non-interactive/mixed modes)". Immediate.
10. **Skip Policy** — Select: Never, If outputs exist, Manual. Immediate.
11. **On Failure** — Select: Retry, Skip, Fail. Immediate.
12. **Max Retries** (shown only when onFailure = retry) — number input, min 0, max 10, width 120. Immediate.
13. **Divider**
14. **Tools** — Autocomplete multiple, placeholder "Select tools...". Immediate.
15. **MCP Servers** — Autocomplete multiple, placeholder "Select MCP servers...". Immediate.
16. **Skills** — Autocomplete multiple, placeholder "Select skills...". Immediate.
17. **Mount repositories switch** — default `true`. Helper: "Repositories are selected when running the workflow". Immediate.
18. **BMAD Method switch** — default `false`. Helper: "Enable the BMAD methodology for this step". Immediate.
19. **Dependencies** — Autocomplete multiple, shows all other steps by "{position}. {name}". Helper: "No dependencies — this step can run in parallel with other root steps" or "This step will start after all selected steps complete". Immediate.
20. **Sub-steps Accordion** — "Sub-steps ({count})". Each sub-step:
    - Position #{N}, Name TextField (saves onBlur), Required switch, reorder up/down, delete
    - Description TextField (saves onBlur)
    - Instructions TextField multiline minRows 3 (saves onBlur)
    - "**+ Add Sub-step**" button: name "Sub-step {N+1}", position N+1, required true
21. **Input Asset Specs** — Add/remove rows: Name, Type (default "file"), Required switch, delete
22. **Output Asset Specs** — Same + Name Pattern field

### Delete Step Confirmation
"Delete Step" / "Are you sure you want to delete this step? This action cannot be undone." / Cancel + "Delete" (error)

### Empty States
- No steps, nothing selected: wrench emoji 🔧, "No steps yet", "Add your first workflow step to get started", "Add First Step" button
- Steps exist, nothing selected: same emoji, "Select a step to configure", "Click on a step in the sidebar to edit its configuration"

---

## 9. Workflow Runs

**Route:** `/company/projects/:projectId/workflow-runs/:runId`

### Header
- Breadcrumbs: Projects → Project → Runs
- Workflow name (title)
- State badge (uppercase, colored: running=primary, completed=green, failed=red)
- Duration (live-updating, JetBrains Mono monospace)
- Step counter: "{completed}/{total} steps"
- **"Cancel Workflow"** button (outlined, red, small) — only when `isRunActive`

### Tab Bar
- "Steps" tab
- "Workflow Assets" tab — **disabled when run is active**

### DAG Timeline (horizontal scrollable strip)
Steps grouped into waves by dependency graph. Each step chip:
- **Status indicator** (20×20px rounded circle):
  - `completed`: green bg, white "✓"
  - `running`: blue bg, white "●", **pulse animation** (2s infinite, opacity 1→0.6)
  - `waiting_input`: orange bg, white "✋", same pulse
  - `failed`: red bg, white "✗"
  - `cancelled`: gray bg, white "✕"
  - `skipped`: disabled bg, white "→"
  - `pending`: white bg, 2px divider border, position number
- Step name (12px, fontWeight 500)
- Duration (10px, JetBrains Mono) — only if started
- **Past failures badge** (top-right, absolute): red circle (16×16) with failure count. Tooltip lists each failure's error message.
- **Wave connectors:** horizontal line (16×2px) between waves. Green if all steps in wave completed, gray otherwise.
- **Active border:** blue when selected.
- Click selects step.

### Auto-follow
When `currentStepRun` changes (new running/waiting step), auto-selects it.

### Terminal Panel (left, flex 1)
- Dark background (#0D0D0D), header (#1A1A1A) shows "■ Terminal — {stepName}"
- If step has `terminalSessionId`: renders `<TerminalSessionWidget>` (showEditor=false)
- No session placeholder messages:
  - 'Terminal for "{stepName}"' + "No terminal session assigned yet"
  - 'Select a step to view terminal' + "Select a running step from the timeline above"
  - Hint (when running + has session + not auto-run mode): 'Done with this step? Use "Finish agent session" in the right panel...'

### Right Panel (260px)
**Sub-steps list** (when step has sub-steps):
- Header: "SUB-STEPS" (uppercase, 11px) + "{completed}/{total}" counter
- Each: status indicator (18×18 rounded 4px, same color scheme but ✓/●/→/number), name (11px), optional note (10px italic)
- Step Note section (when `stepNote` exists)

**Finish Agent Session** (when `canFinishStepSession` = running + has session + not auto-run):
- Description: "Stop the agent when you are satisfied with this step. The workflow will collect outputs and continue."
- Button: "Finish agent session" / "Finishing…" (contained, secondary, fullWidth)

**Action buttons** (when step is `waiting_input` and run is active):
- Label: "Waiting for decision" (warning, 11px bold)
- "Approve & Continue" (contained, primary, fullWidth)
- "Skip" (outlined, fullWidth) → opens Skip dialog
- "Retry" (outlined, warning, fullWidth)

**Failed step** (when step failed + error message):
- "Step failed" (error, 11px bold) + error message (10px)

### Skip Dialog
Title: "Skip Step". TextField: "Reason (optional)" (multiline minRows 3). Buttons: Cancel, "Skip Step" (contained).

### Workflow Assets Tab
Grouped by step. Per group: step label + "{N} file(s)" chip. Per asset: name, meta "{contentType} · {size}", download button (if URL exists), "Promote to Project Assets" button.

**Promote Dialog:** Title "Promote All Artifacts" or 'Promote "{name}"'. Body: "This will create project-level assets from workflow artifacts..." Folder TextField (optional, placeholder "Leave empty for root"). Buttons: Cancel, "Promote" / "Promoting..."

### StatusBar (bottom)
28px height, sections separated by 1px dividers:
- AGENT label + value
- Status dot (colored, animated for running) + label
- USER + value
- DURATION + value (JetBrains Mono)
- COST + $X.XX (green, JetBrains Mono)

### Workflow Runs Widget (table)
- State filter: Select (All, Running, Completed, Failed, Cancelled, Pending)
- 10s polling
- Columns: Status (icon chip), Workflow (name + #id monospace), Mode (Interactive/Auto-run/Custom), Steps ({completed}/{total}), Duration, Started (relative + tooltip full date), Action (OpenInNew for running/paused)

---

## 10. Run Workflow Modal

**Title:** "Run: {workflowName}" (20px, 600 weight)

### Execution Mode
Select with 3 options:
- "Interactive — pause at each step for review"
- "Fully automatic — run all steps without stopping"
- "Custom — choose which steps to auto-run"

**Wave visualization** (interactive/automatic modes): step chips grouped by wave, arrows between waves. Green chip = auto, gray = interactive. Legend shown.

**Custom mode:** Per wave: left border (info.main if parallel), wave label ("Start" or "After {deps}"), per step: checkbox + name + auto/interactive chip + "requires input" warning chip (when `!allowNonInteractive`). Disabled checkboxes for non-auto-runnable steps.

### Agent Runtime
Select of configured agents. "No configured agents" text when empty. Helper: "AI agent that will execute workflow steps"

### Repositories
Autocomplete multiple, placeholder "Select repositories to mount...". Helper: 'Selected repos will be available to steps that have "Mount repositories" enabled'

### Input Assets
Autocomplete multiple, placeholder "Select assets to include...", grouped by folder. Excludes deleted assets. Helper: "Project assets that will be available as inputs to workflow steps"

### Buttons
Cancel + "Run Workflow" / "Starting..." (disabled when creating or no runtime)

---

## 11. Aixle Builder

### Landing Page (`/company/projects/:projectId/aixle-builder`)
- Hero: `AutoFixHighIcon` (48px) + "Aixle Builder" + description
- **Agent Runtime** — Select with colored dots per agent
- **Model** — Select (shown when models available): "Default" + model options
- **Project Assets** — Autocomplete multiple with checkboxes (shown when assets exist)
- **Start button** — "Start Builder" or "Continue Active Session" (if active session exists). Disabled when starting or no runtime.
- **Previous Sessions table** — Session (#id), Status (colored chip), Runtime, Started, Open button

### Session View (`/company/projects/:projectId/aixle-builder/:runId`)
Split layout:
- **Left:** `<TerminalSessionWidget>` (showEditor=false)
- **Right:** 3 tabs:
  - **Activity (N)** — `<MetaActivityLog>`: newest-first list, per item: entity icon (18px) + entity name (13px bold) + action label + timestamp. 21 action types mapped to labels. Entity types: Workflow, Step, SubStep, Agent, Tool, Skill, MCPServer, BoardColumn, Board, ColumnWorkflowBinding.
  - **Workflows** — `<WorkflowsListPreview>`: polls every 10s, accordion per workflow showing name, step count, description.
  - **Board** — `<BoardPreview>`: polls every 10s + refreshes on board-related activities. Shows columns with name, purpose, workflow binding (⚡ auto or 👆 manual + workflow name).

**Header:** Back button + "Aixle Builder" + state chip + #id. "Finish Session" button (warning outlined, shown when active). "Live" chip (green, shown when WebSocket connected).

### Run View (workflow-run based)
Similar but uses `useGetWorkflowRunQuery` with 5s polling + `useWorkflowRunChannel`. Shows single `<WorkflowPreview>` instead of list. Terminal placeholder messages based on run state.

---

## 12. Terminal Sessions

### Session Launch Widget (Form)
**Fields:**
1. **Agent Runtime** — ToggleButtonGroup (exclusive). Each toggle colored by agent. Disabled agents show tooltip "Not configured — complete Onboarding first".
2. **Model** (shown when agent selected) — Autocomplete, placeholder "Default (runtime selects)", loads lazily on open.
3. **Divider "Optional Configuration"**
4. **Agent Persona** — Autocomplete (agents list)
5. **Tools** — Autocomplete multiple
6. **Skills** — Autocomplete multiple
7. **MCP Servers** — Autocomplete multiple
8. **Assets** — Autocomplete multiple (folder/name labels)
9. **Repositories** — Autocomplete multiple (fullName labels, purpose in caption)
10. **Divider "Execution Mode"**
11. **Mode toggle** — "Interactive" / "Automatic". Switching to interactive clears prompt.
12. **Initial Prompt** (automatic only) — required TextField multiline minRows 3, error "Prompt is required for non-interactive mode"
13. **Divider "Context"**
14. **BMAD Method** — Switch
15. **Start Session** — large contained Button, colored by agent. Disabled when `!canSubmit || isCreating`.

**Active Session View:**
- Header: agent label, state chip, session ID, container ID (first 12 chars monospace), error message (truncated 300px), Finish button (red), New Session button
- Stopping overlay: red spinner + "Stopping session…"
- Ended state: "Session {state}" + "Start New Session" button
- Session complete snackbar: "Session completed" with "All Sessions" action

### Terminal Session Widget (Dual-pane iframes)
- **Editor panel:** VS Code Server iframe (`session.ideUrl`), sandbox permissions, loading overlay "Loading editor..."
- **Terminal panel:** ttyd iframe (URL converted from `wss://` → `https://`, `/ws` stripped), loading overlay "Connecting to terminal..."
- **Resizable split** (`react-resizable-panels`): editor default 66%, terminal 34%, separator 4px (#3d3d3d, blue on hover)
- **Collapse:** button on separator (ChevronLeft), double-click separator toggles, ChevronRight strip when collapsed
- **State screens:** no session → "No session selected", error → error message, loading → green spinner, not ready → spinner + "Starting container…", finished/failed → status message + SessionSummaryCard

### Session History Widget (Table)
- **Filters:** Agent type Select, State Select
- **20 per page, 15s polling**
- **Columns:** ID (#id monospace), Agent (colored chip), Type (Standalone/Workflow step/Auth setup/Tool setup), Status (chip + optional "N pending" warning chip for unreviewed artifacts), User (truncated), Project (truncated, hidden when project-scoped), Tokens (formatted + tooltip breakdown), Cost ($X.XX monospace, bold when >0), Models (outlined chips), Duration, Started (relative + tooltip), OpenInNew (for ready sessions only)
- **Pagination** at bottom

### Session Summary Card
Sections (all conditional on data existence):
- Agent chip + Mode chip + Project name
- Resource counts: repos, tools, skills, MCP (colored outlined chips)
- Initial prompt (monospace, truncated 200 chars)
- Models chips + cost ($X.XX green monospace)
- Token grid: input, output, cache_read, cache_write + total row
- Artifacts: logs count chip, pending outputs chip (warning), "Outputs reviewed" chip (success)

---

## 13. Session Artifacts

**Route:** `/company/sessions/:sessionId/artifacts`

- **Already reviewed:** Alert "Outputs for this session have already been reviewed."
- **No artifacts:** Alert "No outputs collected from this session."
- **Artifact table:** Checkbox (+ select all), File (DescriptionIcon + name), Size, Type, Download (DownloadIcon)
- **Actions:** "Save selected (N)" (disabled when none), "Dismiss all" (warning outlined)
- **Review logic:** selected → 'save', unselected → 'dismiss'. Success: snackbar + navigate back.

---

## 14. Project Overview Dashboard

**Polling:** 60-second auto-refresh.

### Summary (4 stat cards)
- Sessions Launched (PlayCircleIcon blue)
- Total Spend (AttachMoneyIcon green, cents→dollars, $Xk for ≥1000)
- Workflows (WorkflowsIcon info blue)
- Board Tasks (ViewKanbanIcon warning orange)

### Two-column Layout
**Left — Recent Activity:**
- Color-coded dot by event type (13 event types mapped to specific colors)
- Description text + "{actorName} · {relativeTime}"

**Right — Workflow Runs:**
- 4 progress bars: Completed (green), In Progress (blue), Failed (red), Queued (orange)

### Board Task Distribution
Grid of column cards: count (28px bold) + column name. "Total" card (primary bg).

---

## 15. Project Analytics

### Filters
- **Scope:** ToggleButtonGroup "User" (PersonIcon) / "Project" (FolderIcon)
- **Tags:** Autocomplete multi-select
- **Task Type:** Select (from API + "All types")
- **Period:** Select: "Last 7 days" / "Last 30 days" / "Last 90 days" / "Last year"

### Charts (all Recharts)
1. **Summary** — 5 stat cards: Total Sessions, Total Cost, Total Tokens, Avg Cost/Session, Workflows Run
2. **Agent Activity Trend** — stacked AreaChart by agent type (7 colors)
3. **Agent Type Distribution** — donut PieChart (innerRadius 55, outerRadius 85, paddingAngle 3)
4. **Daily Cost** — AreaChart (orange #ff9800 gradient)
5. **Daily Token Consumption** — AreaChart (cyan #00bcd4 gradient)
6. **Session Source Breakdown** — solid PieChart with percent labels (6 colors)
7. **Session Duration Histogram** — BarChart with HSL-rotating colors

### Workflow Costs (embedded panel)
- 7 stat cards: Total Cost, Total Tokens, Input/Output Tokens, Workflows, Avg Cost, Avg Time
- Cost Over Time (AreaChart), Token Consumption (AreaChart)
- Cost per Workflow (horizontal BarChart), Tokens per Workflow (stacked horizontal BarChart)
- Workflow Breakdown Table: workflow name + color dot + progress bar, cost, tokens (in/out/total), runs chip, avg/total time

---

## 16. Agents Management

**Dual scope:** company (`/company/agents`) and project (tab in project page).

### Table Columns
AGENT (emoji icon box + title + name in JetBrains Mono) | SCOPE (only project context) | PERSONA (truncated, tooltip) | ACTIONS

### Form Dialog
| Field | Placeholder | Validation | Notes |
|-------|------------|-----------|-------|
| Name | "my_agent" | required, max 100, regex `^[a-z][a-z0-9_]*$` | JetBrains Mono, disabled in edit, auto-lowercase |
| Icon | — | optional, max 10 | EmojiPicker component |
| Title | "Business Analyst" | required, max 200 | — |
| Persona | "Senior analyst with deep expertise..." | required, max 5000 | multiline 4 rows |
| Communication Style | "Speaks with precision..." | optional, max 2000 | multiline 2 rows |
| Principles | "Ground findings in verifiable evidence..." | optional, max 2000 | multiline 2 rows |

**Edit/delete guards:** In project context, only project-scoped agents editable. Company agents show "Company-managed".

---

## 17. Tools Management

### Table Columns
TOOL (displayName + name monospace) | SCOPE | DOCKER IMAGE (monospace, or "Built-in" chip) | FILES (chip "{N} files") | ACTIONS

### Form — 3 Tabs

**Tab "Basic Info":** Name (regex, monospace), Display Name, Description, Docker Image ("python:3.11-slim"), Command ("python /app/script.py --query {{query}}", monospace)

**Tab "Files":** Per file: Path (must start with `/workspace/`), content mode toggle (Text/Upload). Text: CodeMirror editor (vscodeDark, auto-language detection). Upload: drag zone + file info. Delete per file.

**Tab "Config Items":** Autocomplete of company config items.

### Scope Badges
system=purple, company=gray, project=green, overrides_company=amber

---

## 18. Skills Management

### Table Columns
NAME (monospace) | TITLE | KIND (Internal/Custom) | SCOPE (project only) | DESCRIPTION (truncated) | ACTIONS

### Form
Name (allows hyphens: `^[a-z][a-z0-9_-]*$`), Title, Content (multiline 10 rows, max 50000, JetBrains Mono), Description

Internal skills: not editable.

---

## 19. MCP Servers Management

### Table Columns
Name (displayName + name) | URL (truncated) | Transport (chip: "HTTP"/"SSE"/"STDIO") | Scope | Status ("Enabled"/"Disabled") | ACTIONS

### Form (transport-aware)
- Name, Display Name, Transport (Select: HTTP/SSE/Stdio)
- **HTTP/SSE:** URL field + Headers (dynamic key-value list with `ConfigItemValueField` for values)
- **Stdio:** Command field (monospace) + Environment Variables (dynamic key-value list with `ConfigItemValueField`)
- Description, Enabled switch

### ConfigItemValueField
Toggle between plain text and config item reference. Config item mode shows Autocomplete of company config items. References stored as `"config_item:NAME"`.

---

## 20. Config Items

### Table Columns
NAME (JetBrains Mono) | TYPE (Secret=red / Variable=blue) | VALUE (masked "••••••••" for secrets) | SCOPE | DESCRIPTION | ACTIONS

### Filters
Search (placeholder "Search by name...") + Type Select (All/Secret/Variable)

### Form
- Type toggle (create only): Variable / Secret. Helper: "Secrets are encrypted and masked" / "Variables are stored as plain text"
- Name: UPPERCASE only (`^[A-Z0-9_]+$`), auto-transforms, placeholder "MY_CONFIG_VARIABLE", disabled in edit
- Value: password type for secrets (with visibility toggle). In edit+secret: label "New Value (leave empty to keep current)", not required
- Description

---

## 21. Integrations

**Card layout** (not table).

### Connect Menu
Dropdown: "GitHub" (opens external GitHub App URL) / "GitLab" (opens PAT dialog)

### GitLab Dialog
"Enter a GitLab Personal Access Token with **api** scope..." Password field + Connect button.

### Per Integration Card
Provider icon, name, "Connected by {name}", status chip, scope chips. Edit button (GitHub settings link, only for own integrations). Delete button.

### Project Context
Separated sections: "This project" + "Company-wide (read-only here)"

---

## 22. Repositories

**Card layout.**

### Per Repository Card
Lock/Public icon, fullName, purpose (italic), "{branch} · {integration}", scope chip. Edit/Delete buttons.

### Add Dialog
1. Integration Select (if >1 active)
2. Repository Autocomplete (lock/public icon, fullName, description, defaultBranch). Already-added repos disabled with "added" label.
3. Source Branch Autocomplete (auto-selects default)
4. Purpose TextField (multiline, placeholder '"Our main Rails app" or "React template for new projects"')

### Edit Dialog
Source branch (Autocomplete freeSolo) + Purpose

---

## 23. Assets Management

### Table Columns
NAME (+ source badge if not upload) | FOLDER | SIZE (monospace) | VERSION ("v{N}" + total count) | SCOPE | DATE | ACTIONS (5 buttons: Preview, History, Download, Edit, Delete)

### Upload Dialog
- Drag & drop zone ("Drag & drop or click to select files"), max 1 GB, multiple files
- File list with name, size, delete
- Upload progress bar
- Folder Autocomplete (freeSolo, suggests existing folders)
- Uses Uppy with AWS S3 presign

### Asset Preview
Multi-format: Markdown (react-markdown + raw toggle), Code/Text (monospace pre), Image (centered img), Binary (download prompt). Header: extension chip, size, date, download button.

### Version History Dialog
Table: version "v{N}" + "latest" chip, date, size, type, source, download. Close button.

### Soft Delete
"The asset will be moved to trash. You can restore it within 30 days." Multi-version warning.

---

## 24. Company Members

### Filters
Search (debounced 300ms) + Role (All/Admin/Employee) + Status (All/Active/Pending/Archived)

### Table Columns
User (name + email) | Role (chip: admin=blue, employee=green) | Status (chip: active=green, pending=yellow, archived=gray, suspended=red) | Invited (date + "by {name}" or "Self-registered") | Actions (MoreVert menu)

### Context Menu
- Active → "Archive" (ArchiveIcon)
- Archived/Pending → "Activate" (CheckCircleIcon)
- Employee (not self) → "Make Admin"
- Admin (not self, not last admin) → "Make Employee"
- Admin (last admin) → "Make Employee" (disabled, tooltip "Cannot demote the last admin")
- Not self → Divider + "Delete" (red, window.confirm)

### Invite Dialog
Email (placeholder "user@{emailDomain}"), Name (placeholder "John Doe"), Role (Employee/Admin). Validation: valid email, name required max 100.

### Pagination
10/25/50 per page, 1-indexed server-side pages.

---

## 25. User Profile

### Profile Form
- Email (read-only, LockIcon, tooltip "Email is managed by Google OAuth...")
- Display Name (min 2, max 100)
- Preferred Agent Language (11 options: en, ru, es, de, fr, ja, zh, pt, it, pl, uk)
- Company (read-only)
- Role badge (super_admin=purple, admin=blue, employee=gray)
- Save button (disabled when not dirty/valid)

### Default Agent Selector
Card "Default Agent Runtime". Select of configured credentials. Helper: "Used when starting new sessions..."

### Default Model Selector
Card "Default Models". Per credential: agent label + Autocomplete (lazy-loaded models). Placeholder "Default (runtime selects)".

### Agent Credentials Section
See below.

---

## 26. Agent Credentials & Auth

### Credentials Section (Profile page)
Per agent (4 total): card with color bar, CheckCircle (green) or RadioButtonUnchecked (gray), name, description.
- Configured: metadata "Configured {date} · Last used {date} · Expires {date}" + "Connected" chip (green). Button: "Re-authenticate" (outlined, RefreshIcon)
- Not configured: Button: "Authenticate" (contained)

### Auth Terminal Flow
Full-screen dialog (maxWidth lg, 80vh):
1. Optional env fields step (currently no agents need this)
2. Terminal step: "Start Authentication" button → creates auth_setup session → `<TerminalSessionWidget>` (showEditor=false)
   - Header shows: agent type, route token (monospace), state, "Auth detected" indicator
   - **Auth polling:** Every 2 seconds, fetches `/t/{routeToken}/fs/auth`, checks `{ authenticated: true }`
   - "Save Authentication" button (green, disabled until auth detected) / "Cancel" button (red outlined)
3. Completed step: ✅ "Authentication Complete" + "Credentials have been saved securely."

**Credential save polling:** After auth detected, polls `refetch()` every 500ms, max 20 attempts, waiting for Temporal workflow.
