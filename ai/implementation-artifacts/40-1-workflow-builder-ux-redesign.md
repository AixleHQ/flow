# Story 40.1: Workflow Builder — Full UX Redesign

Status: ready-for-dev

## Story

As a **workflow author** (admin or project collaborator),
I want the Workflow Builder page to be restructured into three flat tabs (Sessions / Triggers / Base Resources) with a tree-nav sidebar that nests Steps inside their parent Session, inline autosave, and a redesigned theme-compliant header,
so that I can configure all aspects of a workflow from a single, well-organised page without navigating away to modals or overlay panels.

## Background — GitHub Issue #212

This story implements the full design handoff from issue [#212](https://github.com/palad-ai/palad-app/issues/212) "Workflow page UX and redesign".

Designer artefacts (reference HTML) are in `artefacts/` at project root:
- `artefacts/aixle-workflows-complete_4_3_7.html` — **canonical reference** (latest colours + renamed terminology)
- `artefacts/aixle-workflows-complete_2.html` — AI Builder integrated variant
- `artefacts/aixle-workflows-complete_3.html` — AI Builder separated variant

The `_4_3_7` file is the definitive reference for all implementation decisions below.

---

## Acceptance Criteria

### AC1: Terminology rename — Step → Session, Sub-step → Step

- All user-visible labels updated: "Step" → "Session", "Sub-step" → "Step"
- Left-nav tree uses "Session" for top-level rows and "Step" for nested rows
- "Add a session…" ghost row; nested inline form reads "Step name…"
- Step-detail panel title changes dynamically: shows session name when a session is selected, shows step name when a step is selected
- Backend model names (`Step`, `SubStep`, `WorkflowStep`) remain unchanged — this is a display-only rename

### AC2: Post-create redirect to builder

- After submitting the "New Workflow" modal, redirect directly to the BuilderPage for that workflow instead of staying on the WorkflowsPage list
- Matches designer note: "after saving in the create modal, now redirects straight into the workflow's config page"

### AC3: Header — inline editable name & description with autosave chip

- Workflow name: an `<input>` that looks like a heading (transparent border on idle, visible on hover/focus), saves on change via 500ms debounce
- Workflow description: `<textarea>` that autosizes (single-row idle, expands on focus), saves via 500ms debounce
- A persistent "Saving… / Saved" chip in the header (spinner while in-flight, check icon when settled)
- The chip is the single autosave signal for the whole page — no per-section save buttons
- "Back to Workflows" link in the header
- "Run" button (accent-filled, disabled if no session has instructions)
- Scope tag ("Project" or "Company") next to the workflow name

### AC4: Three-tab layout — Sessions / Triggers / Base Resources

- Tab bar directly below the header, three tabs: **Sessions**, **Triggers**, **Base Resources**
- Tabs use `Tabs` from Mantine with bottom-border active indicator in `--accent` colour
- Each tab shows a fully scrollable content area; the split-pane layout only applies to the Sessions tab

### AC5: Sessions tab — left tree-nav + right editor

**Left tree nav** (fixed width ~300px, `bg-raised` background, dark border on right):

Session rows:
- Numbered circle badge (1, 2, …) — accent-coloured ring when active
- Session name — accent-coloured text when active
- Trash delete button — visible on hover / active row
- Drag handle (`ti-grip-vertical`) — appears on hover, before the number badge
- **Status badge chips** below the name (row-tags area), rendered from session state:
  - `AUTO` — orange/accent filled badge (`tag-auto`) when `allowNonInteractive` is true
  - `· BMAD` — neutral badge with a dot prefix when `bmadEnabled` is true
  - `ROOT` — neutral badge when session has no dependencies (`dependsOnStepIds` empty)
  - `↳ AFTER {Session Name}` — neutral badge with arrow icon when session depends on another (shows name of dependency)
- Drag-to-reorder sessions; session's nested step sub-tree moves with it

Step rows (nested inside session, indented ~26px):
- Lettered badge (`a`, `b`, …) — square, 14×14px
- Step name — accent-coloured when active
- Trash delete button — visible on hover / active
- Drag handle — appears on hover, for reordering steps within a session

Ghost rows:
- Per-session: `+ Add a step…` link below last step of each session
- Global: `+ Add a session…` dashed-border row at the bottom of the full list
- On click → inline input appears (focused), number/letter badge updates live
- Enter → creates item and selects it; Esc → cancels; blur → cancels (with `onBlur`)
- "Add a session…" shows `↵ confirm · esc cancel` hint; step inline shows `↵ · esc`

Active/selected state for session row:
- Background: `accent-dim` (`rgba(207,107,74,0.12)`)
- Border: `rgba(207,107,74,0.2)`
- Number badge: accent background + accent border
- Session name: accent colour

**Right editor panel** (scrollable, max-width 680px, padding 24px 28px):

All sections use `sec-label` header with icon + uppercase label text + bottom border.

**DEFINITION section** (shown for both sessions and steps):
- Session/Step name — large heading-style `TextInput` (18px, 700 weight, `Sora` font), transparent background idle; hover shows border, focus shows accent border. Placeholder: "Session name…" or "Step name…" depending on mode.
- Description — `Textarea` (2 rows), placeholder: "One-line summary of what this does…"
- Instructions (sessions only, required field — red dot indicator):
  - Info tooltip: "The prompt the AI agent receives. Use `{{artifact_name}}` to reference assets."
  - Help text: `Use {{artifact_name}} to reference workflow assets. Prompt guide ↗`
  - Tall `Textarea` (min 180px / ~10 rows), placeholder mentions `{{artifact_name}}`
  - Footer row: character count left (`0 characters`) + "Expand" button right (toggles between 180px and 400px height)

**OPTIONS section** (steps only):
- "Required" toggle (`Switch`) — "Must complete for the parent session to proceed."

**EXECUTION section** (sessions only):
- 2-column grid:
  - **Agent** — custom `Select` dropdown with agent icon + name. Options: "No agent" + list of agents from props. Agent icon is 18×18px rounded square.
  - **Execution Environment** — custom dropdown (not a plain `Select`): each option shows a runtime logo image (18×18px). Options with logos: None (default), Claude Code, Cursor CLI, Codex, Gemini CLI. The logo images are base64-encoded PNGs (available in the HTML reference).

**RESOURCES section** (sessions only):
- Info note bar: `ℹ Session-level additions — stacked on top of Base Resources` (accent left border)
- `Tools — custom functions this session can call` → `MultiSelect` with chip tags
- `MCP Servers — external providers` → `MultiSelect` with chip tags
- `Skills — capability modules` → `MultiSelect` with chip tags
- Each group shows "None added" when empty

**DEPENDENCIES section** (sessions only):
- Green-left-border note: "No dependencies — this session can run in parallel with other root sessions." OR "Waits for **{Session Name}** to complete before starting." (updates live)
- **Run after** — `Select` / `MultiSelect` where options are the names of other sessions in the workflow (populated dynamically); placeholder "Select sessions this session depends on…"
- Selecting a dependency updates the `ROOT` / `↳ AFTER {Name}` badge in the tree nav immediately

**DATA FLOW section** (sessions only):
- **INPUTS — files this session reads**: `+ Add input` button; each row: name text input, asset_type select, required toggle, delete button
- **OUTPUT ARTIFACT — file this session produces**: `+ Add output` button; each row: name, asset_type, required, name_pattern, delete

**BEHAVIOR section** (sessions only):
- *Run control* sub-group:
  - "Auto-run available" toggle — "Skip user approval in non-interactive/mixed modes." Toggling this immediately updates the `AUTO` badge in the tree nav.
  - **Skip Policy** select: `Never` / `If outputs exist` / `Manual` + contextual consequence text below (e.g. "This session always runs when the workflow is triggered.")
  - **On Failure** select: `Fail` / `Retry` / `Skip` + contextual consequence text below (e.g. "The entire workflow run stops immediately if this session fails.")
- *Environment* sub-group:
  - "Mount repositories" toggle — "Makes project repositories available to the agent during this session."
  - "BMAD Method" toggle — "Enable the BMAD methodology for this session. Learn more ↗" Toggling updates the `· BMAD` badge in the tree nav immediately.

### AC6: Triggers tab — rendered inline (no sliding panel for list)

**Tab header**: "Triggers — how this workflow launches" heading + subtitle "Any enabled trigger can start a run. Off-board triggers (Slack, webhook) decide what task the run is about via subject."

**Trigger card grid** (`display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px`):

Each trigger card (`trig-item`):
- Card top row: type icon (18px, `ti-layout-columns` / `ti-clock` / `ti-brand-slack` / `ti-webhook`) + trigger title + meta text below title
- Card bottom row: event chip (e.g. `BOARD.COLUMN_CHANGED`, `SCHEDULE.CRON`, `SLACK.MESSAGE`, `WEBHOOK.RECEIVED`) + optional `Disabled` badge + right side: on/off `Switch`, divider, edit pencil button, delete trash button
- Trigger title formatting:
  - Column: `Task enters "{column name}"`
  - Schedule: human-readable cron ("Weekdays at 9:00 AM") or `Cron {expr}`
  - Slack: `Slack message {contains} "{pattern}"` or `Any Slack message`
  - Webhook: `Incoming webhook`
- Meta text formatting:
  - Column: `{mode} · cooldown {N}s`
  - Schedule: `{cron} · {timezone}`
  - Slack: `channel {id}` or `any channel`
  - Webhook: `verification: {type}` + optional ` · when {field} {op} {value}`
- Disabled card: full card opacity reduced, "Disabled" chip shown in bottom row

**"+ Add a trigger" tile** — always appended after the last trigger card; dashed border, centered `+` icon and label.

**Empty state** (when no triggers exist, replaces the card grid):
- Bolt icon badge centered
- Heading: "Add your first trigger"
- Subtitle: "Choose how this workflow should launch. You can add more than one — any enabled trigger starts a run."
- 2×2 grid of clickable option tiles — each has: icon, name, description:
  - `ti-layout-columns` / "Task enters column" / "When a board task moves into a chosen column"
  - `ti-clock` / "On schedule" / "On a recurring cron timer"
  - `ti-brand-slack` / "Slack message" / "When a matching message is posted"
  - `ti-webhook` / "Incoming webhook" / "When an authenticated request arrives"
- Clicking any tile opens the Add Trigger side panel pre-selected to that type

**Add/Edit trigger side panel** (right side panel, NOT a full-width overlay):
- Slides in from the right of the triggers tab area; a dark scrim covers the trigger list behind it
- Panel heading: "Add trigger" or "Edit trigger"
- Close `×` button top-right
- "Trigger type" dropdown — disabled when editing (type is locked, shown with a lock note)
- **Per-type fields** (shown/hidden based on selected type):
  - *Task enters column*: Column (`Select`), Mode (`Auto` / `Manual` segmented control), Cooldown (s) (`NumberInput`)
  - *On schedule*: Cron input (`TextInput`), cron human-readable hint below (e.g. "Runs: At 09:00 AM, Monday through Friday"), Timezone (`Select`), Subject (`Select` — "None — project-level run" or "Create a task · {SessionName}")
  - *Slack message*: Channel id (`TextInput`, placeholder "C0123ABC (blank = any)"), Text match (`Select`: contains / equals / regex / starts with) + Pattern (`TextInput`), Subject (`Select`)
  - *Incoming webhook*: Verification (`Select`: None / HMAC-SHA256 / Bearer token), Secret (`PasswordInput`, optional), "Only when (optional)" section with Field + Op + Value inputs (`TextInput` + `Select` + `TextInput`), Subject (`Select`)
- Panel footer: "Cancel" ghost button + "Add trigger" / "Update trigger" accent button
- **Subject select** options are populated dynamically from the current sessions list: "None — project-level run" + "Create a task · {SessionName}" for each session

### AC7: Base Resources tab — redesigned flat layout

**Tab header**: "Base Resources" heading + subtitle "Default resources available to every session. Sessions can add their own on top."

**Inherit toggle card** (full-width, `bg-card` background, border):
- "Inherit all project resources" label (primary text, 14px bold)
- Sub-label: "Tools, skills, MCP servers, and assets from the project level are included automatically."
- `Switch` on the right end of the row (maps to `workflow.inheritAllProjectResources`)

**2-column grid** below the toggle card (`grid-template-columns: 1fr 1fr; gap: 16px`):
- **Tools** — `MultiSelect` with chip tags + "None added" empty note
- **Skills** — `MultiSelect` with chip tags + "None added" empty note
- **MCP Servers** — `MultiSelect` with chip tags + "None added" empty note
- **Assets** — `MultiSelect` with chip tags + "None added" empty note

This is the existing `BaseResourcesSection` component content, moved from its current Accordion position in the Sessions tab to this standalone tab. Remove `BaseResourcesSection` accordion from the Sessions tab.

### AC8: Design tokens — warm/terracotta dark theme

All new elements must use the CSS custom properties that already exist in `BuilderPage.module.css` / Mantine theme:

| Token | Value | Usage |
|---|---|---|
| `--bg` | `#0a0908` | Page background |
| `--bg-raised` | `#191817` | Sidebar, header |
| `--bg-card` | `#121110` | Cards, inputs |
| `--border` | `#292726` | Default border |
| `--border-mid` | `#393837` | Hover border |
| `--text-1` | `#d1cfcd` | Primary text |
| `--text-2` | `#9f9d9c` | Secondary text |
| `--text-3` | `#5d5b5a` | Muted/placeholder |
| `--accent` | `#cf6b4a` | Interactive/automation (tabs, active states, primary CTA) |
| `--accent-dim` | `rgba(207,107,74,0.12)` | Soft accent backgrounds |
| `--accent-muted` | `rgba(207,107,74,0.30)` | Accent borders |

**Rule:** Accent colour is reserved for interactive/automation elements only — not used as decoration.

Border radii: 4px / 8px only. Spacing: multiples of 4px (4/8/12/16/24/32px). Font sizes: 10/12/13/14/16/18px. No floating box-shadows — inset highlights only.

### AC9: Autosave — all fields on the page

- Every text field, toggle, and select triggers autosave via existing `apiFetch` + debounce pattern
- Text inputs (name, description, instructions): 500ms debounce
- Selects, toggles: immediate save on change
- Single saving chip in header (shared state across all mutations in-flight)

### AC10: "Run" button state

- Disabled + tooltip "Add instructions to at least one session to run" when no session has non-empty instructions
- Enabled and opens `RunWorkflowModal` when at least one session has instructions

### AC11: "Build with AI" — moved from page to sidebar

The "Build with AI" entry point is **removed from the Workflows page header/toolbar** and replaced with a persistent **AI Builder banner at the bottom of the global sidebar navigation**.

Sidebar banner spec (visible on all pages, always at the bottom of the sidebar):
- Accent-coloured icon badge (wand icon `ti-wand`, 32×32px, `--accent` background)
- Title: "AI Builder" (14px, 600 weight, `--text-1`)
- Subtitle: "Tasks, boards, and workflows — connected, from one prompt." (`--text-2`, 12px, 2 lines)
- "✦ Build with AI" button — full-width, white/light fill (`#e8e5e2`), dark text, 8px radius, 36px height; wand prefix icon

Clicking "Build with AI" navigates to the AI Builder setup page (see AC12).

The existing button/link on `WorkflowsPage` (if any) that previously opened the AI Builder flow must be removed.

---

## Tasks / Subtasks

- [ ] Task 1: Rename terminology in UI only (AC1)
  - [ ] 1.1 Replace all `Step` labels with `Session` in tree-nav and editor panel header
  - [ ] 1.2 Replace all `Sub-step` / `Substep` labels with `Step`
  - [ ] 1.3 Update placeholder text: "Add a session…", "Session name…", "Add a step…", "Step name…"
  - [ ] 1.4 Update BuilderPage title, section labels, empty states

- [ ] Task 2: Post-create redirect to builder (AC2)
  - [ ] 2.1 In `WorkflowsPage.tsx`, after successful workflow create mutation, call `router.visit(Routes.builderProjectWorkflowPath(projectId, newWorkflowId))`
  - [ ] 2.2 Use `Routes.builderCompanyProjectWorkflowPath(project.id, newWorkflowId)` — this helper already exists in `shared/routes.ts` (line ~941)

- [ ] Task 3: Header redesign (AC3)
  - [ ] 3.1 Replace current MUI-style `TextInput` header with transparent inline inputs (name as heading, desc as compact textarea)
  - [ ] 3.2 Add "Saving… / Saved" chip component — single piece of shared state `savingCount: number`, shows spinner when > 0, check when 0
  - [ ] 3.3 Ensure chip is visible in top-right of header row alongside "Back" link and "Run" button
  - [ ] 3.4 Debounced save for name/description hooks into existing `apiFetch(Routes.apiV1ProjectWorkflowPath(project.id, workflow.id), { method: 'PATCH', ... })` — `apiV1ProjectWorkflowPath` exists in `shared/routes.ts`

- [ ] Task 4: Three-tab layout scaffold (AC4)
  - [ ] 4.1 Wrap builder body in Mantine `Tabs` component with `Sessions`, `Triggers`, `Base Resources` panels
  - [ ] 4.2 Style tab bar to match design: accent active indicator, `bg-raised` background
  - [ ] 4.3 Lazy-render tab content (only mount active tab or keep all mounted — choose based on perf)

- [ ] Task 5: Sessions tab — tree-nav + editor (AC5)
  - [ ] 5.1 Extract existing tree nav into `SessionTreeNav` component (left pane, ~300px fixed width, `bg-raised` bg + right border)
  - [ ] 5.2 Implement session row with: numbered badge, name, tag chips row (AUTO / BMAD / ROOT / AFTER), drag handle (hover-only), trash button (hover-only); active row gets `accent-dim` bg + accent border
  - [ ] 5.3 Add step (sub-step) rows nested inside each session — indented 26px, lettered badge (`a`, `b`, …), name, drag handle, trash
  - [ ] 5.4 Inline ghost rows: "Add a session…" global (bottom) and per-session "+ Add a step…"; both open focused inline input on click; `↵` confirms, `Esc` / blur cancels; confirm immediately creates and selects the item
  - [ ] 5.5 Drag-to-reorder sessions via `@dnd-kit/sortable`; sub-tree moves with session; drag-to-reorder steps within a session
  - [ ] 5.6 Re-number session badges (`1, 2, …`) after add/delete/reorder; re-letter step badges (`a, b, …`) after add/delete/reorder within a session
  - [ ] 5.7 Session badge chips (`renderSessionTags`): re-compute and re-render on every field change that affects tags (auto-run toggle, BMAD toggle, dependency change)
  - [ ] 5.8 Extract right-side editor into `SessionEditorPanel` (session selected) and `StepEditorPanel` (step selected); controlled by `editorMode: 'session' | 'step'` + selectedId state
  - [ ] 5.9 **DEFINITION section**: name as heading-style `TextInput` (18px/700/transparent, focus→accent border), description 2-row `Textarea`, instructions tall `Textarea` (min 180px) with character count + Expand toggle + required-field dot + help link; sessions only for instructions
  - [ ] 5.10 **EXECUTION section**: Agent custom select (agent icon 18px + name, options from `agents` Inertia prop), Execution Environment custom select with runtime logos (base64 images in HTML reference)
  - [ ] 5.11 **RESOURCES section**: info note bar (`Session-level additions — stacked on top of Base Resources`); Tools, MCP Servers, Skills each as labeled `MultiSelect` with chips + "None added"
  - [ ] 5.12 **DEPENDENCIES section**: live contextual note; "Run after" `Select` populated from sibling sessions; selecting a dep re-renders tree nav tags immediately
  - [ ] 5.13 **DATA FLOW section**: Inputs list (add/remove rows: name, asset_type, required); Output Artifact list (add/remove rows: name, asset_type, required, name_pattern)
  - [ ] 5.14 **BEHAVIOR section — Run control**: "Auto-run available" `Switch` (→ updates AUTO badge); Skip Policy `Select` (Never/If outputs exist/Manual + consequence text); On Failure `Select` (Fail/Retry/Skip + consequence text)
  - [ ] 5.15 **BEHAVIOR section — Environment**: "Mount repositories" `Switch`; "BMAD Method" `Switch` (→ updates BMAD badge; subsumed from Story 34.3)
  - [ ] 5.16 **OPTIONS section** (step only): "Required" `Switch`

- [ ] Task 6: Triggers tab (AC6)
  - [ ] 6.1 Create `TriggersTab` component — renders tab header, card grid or empty state
  - [ ] 6.2 **Empty state**: bolt icon badge, "Add your first trigger" heading, subtitle, 2×2 option tile grid (column/schedule/slack/webhook icons+names+descriptions); clicking tile opens panel pre-selected to that type
  - [ ] 6.3 **Card grid**: `display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px`; each `trig-item` card renders title, meta, event chip, disabled badge (if off), on/off `Switch`, edit, delete
  - [ ] 6.4 **"+ Add a trigger" tile**: dashed border tile appended after cards; clicking opens Add panel with type unlocked
  - [ ] 6.5 **Add/Edit side panel**: right-side panel with scrim over list; type `Select` (locked on edit with lock note); per-type fields (see AC6 field spec); Subject `Select` populated from sessions list; "Cancel" ghost btn + "Add/Update trigger" accent btn
  - [ ] 6.6 On trigger save/delete trigger mutation via `apiFetch` → `router.reload({ only: ['triggers'] })`
  - [ ] 6.7 Ensure `builder` controller action serializes `triggers` in Inertia props (check `app/controllers/web/projects/workflows_controller.rb`)

- [ ] Task 7: Base Resources tab (AC7)
  - [ ] 7.1 Move `BaseResourcesSection` from Accordion inside Sessions tab to `BaseResourcesTab` component
  - [ ] 7.2 Add "Inherit all project resources" toggle card at top of tab (maps to existing `inheritAllProjectResources` field)
  - [ ] 7.3 Lay out pickers in 2-column grid
  - [ ] 7.4 Remove old `BaseResourcesSection` Accordion from Sessions tab

- [ ] Task 8: Design tokens + CSS (AC8)
  - [ ] 8.1 Audit `BuilderPage.module.css` — ensure all new selectors use the established token variables
  - [ ] 8.2 No floating `box-shadow` on new components — use `border` only
  - [ ] 8.3 Use `--accent` only for interactive states (active tab, active session row, primary button) — not decoration

- [ ] Task 9: Autosave chip + field wiring (AC9)
  - [ ] 9.1 Create `useSavingState()` hook: tracks in-flight count, exposes `withSave(promise)` wrapper
  - [ ] 9.2 Wrap every mutation in `withSave(...)` so chip reflects aggregate state
  - [ ] 9.3 Ensure all new fields (Dependencies, BMAD toggle) call save on change

- [ ] Task 10: Run button guard (AC10)
  - [ ] 10.1 Compute `canRun = steps.some(s => s.instructions?.trim().length > 0)`
  - [ ] 10.2 Disable Run button + show `Tooltip` when `!canRun`

- [ ] Task 11: Move "Build with AI" to sidebar (AC11)
  - [ ] 11.1 Remove "Build with AI" button / link from `WorkflowsPage` header or wherever it currently lives
  - [ ] 11.2 Add AI Builder banner at the bottom of the global sidebar layout component (find the shared layout in `app/frontend/shared/layouts/` or `app/frontend/layouts/`)
  - [ ] 11.3 Banner markup: accent icon badge (`ti-wand`) + "AI Builder" title + subtitle text + "✦ Build with AI" full-width button
  - [ ] 11.4 "Build with AI" button navigates to the AI Builder page via `router.visit(Routes.aiBuilderPath(...))` — verify route name; if the AI Builder page doesn't exist yet, wire button to the existing flow (modal or redirect) that was previously in the header
  - [ ] 11.5 Banner is always visible in the sidebar regardless of which page the user is on (it is part of the global layout, not page-specific)

---

## Dev Notes

### Current File Layout

```
app/frontend/pages/Projects/Workflows/
├── BuilderPage.tsx         # 1512 lines — MAIN FILE TO REFACTOR
├── BuilderPage.module.css  # CSS module, ~60 lines
├── BuilderPage.test.tsx    # Existing tests — must stay green
├── WorkflowTriggersDrawer.tsx  # EXISTS — reuse for Triggers tab
├── WorkflowsPage.tsx       # MODIFY — post-create redirect
└── WorkflowsPage.test.tsx
```

The current `BuilderPage.tsx` is one large file with everything inlined. The refactor should extract sub-components **co-located** in the same folder (no separate features folder — this project uses a flat `pages/` structure without Feature-Sliced Design layers).

### Tech Stack Constraints

- **UI library:** Mantine (v7) — `Tabs`, `TextInput`, `Textarea`, `Select`, `MultiSelect`, `Switch`, `ActionIcon`, `Tooltip`, `Modal`. **Never use MUI** — the project was migrated off MUI.
- **Drag-and-drop:** `@dnd-kit/core` + `@dnd-kit/sortable` — already imported and used for step reorder.
- **API mutations:** `apiFetch` from `shared/lib/apiFetch` — handles CSRF, credentials. **Never use RTK Query or fetch directly.**
- **Routes:** Only typed helpers from `shared/routes` (ts_routes gem). Never hardcode URL strings.
- **Debounce:** `useDebouncedCallback` from `use-debounce` — already used in this file.
- **Form state:** Plain `useState` / `useCallback` — the existing pattern in `BuilderPage.tsx`. No `useForm` from Mantine for the builder fields (they save on blur/change, not on submit).
- **Inertia props:** The page receives `workflow`, `steps`, `agents`, `tools`, `mcpServers`, `skills` via Inertia props. No client-side fetching. Real-time via `useInertiaCableStream` if needed.

### Key Existing Patterns in BuilderPage.tsx

```tsx
// Debounced workflow save (already exists, extend this):
const debouncedSaveWorkflow = useDebouncedCallback(async (fields) => {
  await apiFetch(Routes.apiV1ProjectWorkflowPath(project.id, workflow.id), {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ workflow: fields }),
  });
}, 500);

// Step save pattern:
const debouncedSaveStep = useDebouncedCallback(async (stepId, fields) => {
  await apiFetch(Routes.apiV1ProjectWorkflowStepPath(project.id, workflow.id, stepId), {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ step: fields }),
  });
  router.reload({ only: ['steps'] });
}, 500);
```

### Saving Chip Implementation

```tsx
// Hook to track in-flight saves
function useSavingState() {
  const [count, setCount] = useState(0);
  const withSave = useCallback(async (promise: Promise<unknown>) => {
    setCount(c => c + 1);
    try { await promise; } finally { setCount(c => c - 1); }
  }, []);
  return { saving: count > 0, withSave };
}
```

### Terminology Mapping (display only, backend unchanged)

| Backend model field | Old UI label | New UI label |
|---|---|---|
| `Step` (top-level) | Step | **Session** |
| `SubStep` | Sub-step | **Step** |
| `step.instructions` | Instructions | Instructions |
| `step.name` | Step name | Session name |
| `subStep.name` | Sub-step name | Step name |

### Post-Create Redirect (Task 2)

In `WorkflowsPage.tsx` find the workflow-create form submission handler. After the `apiFetch` POST succeeds and returns the new workflow ID, call:

```tsx
router.visit(Routes.builderCompanyProjectWorkflowPath(project.id, data.workflow.id));
```

Check whether `builderProjectWorkflowPath` exists in `shared/routes`; if not, check the actual route name via `docker compose exec web bundle exec rake routes | grep builder`.

### Dependencies Section (new field)

The backend `Step` model already has `depends_on_step_ids` (array of integers). The `StepResource` serializer must include `depends_on_step_ids`. If not already serialized, add to `app/serializers/step_serializer.rb`:

```ruby
attributes :depends_on_step_ids
```

Frontend: display as a `MultiSelect` where options are other sessions in the workflow (by position label + name).

### Session Badge Tags — `renderSessionTags` logic

Each session row in the tree nav displays a row of small badge chips derived from the session's field values. Re-render tags whenever any of these fields change:

```tsx
type SessionTagProps = {
  allowNonInteractive: boolean;  // → AUTO badge (orange filled)
  bmadEnabled: boolean;          // → · BMAD badge (neutral + dot)
  dependsOnStepIds: number[];    // empty → ROOT badge; non-empty → ↳ AFTER {name} badge
  allSessions: { id: number; name: string }[];
};

// Tag logic:
// 1. if allowNonInteractive → <badge class="tag-auto">Auto</badge>
// 2. if bmadEnabled → <badge><dot/>BMAD</badge>
// 3. if dependsOnStepIds.length === 0 → <badge>Root</badge>
//    else → <badge><arrow↳/>After {name}</badge>  (show first dep name only if single, or count)
```

Tooltips on each badge:
- AUTO: "Runs automatically without approval"
- BMAD: "BMAD methodology enabled"
- ROOT: "No dependencies — runs in parallel"
- AFTER: "Runs after {Name}"

### Trigger Type Constants

```ts
const TG_ICONS = { column: 'ti-layout-columns', schedule: 'ti-clock', slack: 'ti-brand-slack', webhook: 'ti-webhook' };
const TG_EVENTS = { column: 'BOARD.COLUMN_CHANGED', schedule: 'SCHEDULE.CRON', slack: 'SLACK.MESSAGE', webhook: 'WEBHOOK.RECEIVED' };
const TG_NAMES  = { column: 'Task enters column', schedule: 'On schedule', slack: 'Slack message', webhook: 'Incoming webhook' };
```

Trigger title display logic:
- column: `Task enters "{col}"`
- schedule: map common crons to human label (`0 9 * * 1-5` → "Weekdays at 9:00 AM", etc.) or fall back to `Cron {expr}`
- slack: `Slack message {match} "{pattern}"` or `Any Slack message`
- webhook: `Incoming webhook`

Trigger meta line:
- column: `{mode} · cooldown {N}s`
- schedule: `{cron} · {tz}`
- slack: `channel {id}` or `any channel`
- webhook: `verification: {type}` + optional ` · when {field} {op} {value}`

### Skip Policy & On Failure — consequence texts

Skip Policy:
- `Never` → "This session always runs when the workflow is triggered."
- `If outputs exist` → "Skips this session if its output artifacts already exist."
- `Manual` → "You decide at run time whether to run this session."

On Failure:
- `Fail` → "The entire workflow run stops immediately if this session fails."
- `Retry` → "The session is retried automatically before failing."
- `Skip` → "The workflow continues even if this session fails."

### WorkflowTriggersDrawer vs new inline panel

**Decision required at implementation time**: Check whether `WorkflowTriggersDrawer.tsx` already implements the right-side panel with per-type fields. If it does, reuse it directly — just open it from the `TriggersTab`. If `WorkflowTriggersDrawer.tsx` only handles a different UX (e.g. full-overlay), create a new `TriggerFormPanel.tsx` co-located in `pages/Projects/Workflows/` implementing the side-panel pattern shown in the HTML reference. The HTML reference (`_4_3_7.html` — `#tgPanel`, `.tg-panel`) shows a right-side sliding panel, not a full modal.

### BMAD Toggle (from Story 34.3 — ready-for-dev)

Story 34.3 is `ready-for-dev` and adds a BMAD Method toggle to the step editor. When implementing Task 5 (Sessions tab / Behavior section), include the BMAD toggle as part of the Behavior > Environment group. This story subsumes Story 34.3 — no need to implement 34.3 separately.

The field: `step.bmadEnabled` (boolean). Map to `bmad_enabled` via decamelize. Immediate save on toggle.

### BuilderPage.module.css — Existing Tokens

The module already maps to CSS variables:

```css
/* existing in BuilderPage.module.css */
.root { display: flex; gap: 0; height: calc(100vh - 60px); margin: -24px -32px; }
```

New selectors go in `BuilderPage.module.css`. Use the `--bg`, `--bg-raised`, `--accent`, etc. CSS custom properties which are injected by the global Mantine theme setup at `shared/theme/`.

### File Structure After Refactor

```
pages/Projects/Workflows/
├── BuilderPage.tsx              # Lean orchestrator — imports sub-components
├── BuilderPage.module.css       # Extended with new selectors
├── BuilderPage.test.tsx         # Update tests to match new structure
├── WorkflowTriggersDrawer.tsx   # Existing — check if reusable for new panel; if not, keep as-is
├── WorkflowsPage.tsx            # Modified: post-create redirect + "sessions" card label
├── WorkflowsPage.test.tsx
├── SessionTreeNav.tsx           # NEW: left tree nav (sessions + nested steps + tag badges)
├── SessionEditorPanel.tsx       # NEW: right editor when a session is selected (all sections)
├── StepEditorPanel.tsx          # NEW: right editor when a step is selected (Definition + Options)
├── TriggersTab.tsx              # NEW: trigger card grid + first-run empty state
├── TriggerFormPanel.tsx         # NEW (if WorkflowTriggersDrawer doesn't fit): add/edit side panel
├── BaseResourcesTab.tsx         # NEW: extracted from BaseResourcesSection + tab layout
└── SaveChip.tsx                 # NEW: "Saving… / Saved" chip component
```

### Testing Standards

- Backend: none required for this story (UI-only)
- Frontend: Vitest + React Testing Library, co-located `*.test.tsx`
- **Must stay green:** `BuilderPage.test.tsx` — update assertions to match renamed terminology and new component structure
- Run: `docker compose exec -T web ./node_modules/.bin/vitest run app/frontend/pages/Projects/Workflows/`

### AI Builder Sidebar Banner (Task 11)

The banner lives in the global sidebar component — find it with:

```bash
# Find the sidebar/nav layout component:
ls app/frontend/shared/layouts/ app/frontend/layouts/ app/frontend/components/ 2>/dev/null
# or search for the nav item that renders "Workflows" in the sidebar:
rg "Workflows" app/frontend --type tsx -l
```

The banner should be placed **outside the scrollable nav item list**, pinned to the bottom of the sidebar. In Mantine terms, use `NavLink` layout or a flex column with `marginTop: 'auto'` to push the banner to the bottom.

CSS tokens for the banner button (`#e8e5e2` light fill):
```css
.aiBannerBtn {
  background: #e8e5e2;
  color: #1a1816;
  border-radius: 8px;
  width: 100%;
}
.aiBannerBtn:hover {
  background: #f0edea;
}
```

The sidebar collapse state (if the sidebar has a collapsed mode) should hide the subtitle and compress the banner to just the icon badge.

The workflow cards on `WorkflowsPage` currently show "X steps". After the terminology rename they must show "X sessions". Update the card component to use "session" / "sessions" instead of "step" / "steps".

Also confirm the "New Workflow" modal (`createModal`) is already present on `WorkflowsPage`. The modal fields are: Name (required, `TextInput`) and Description (optional, `Textarea`). The "Create workflow" button should call `submitCreate`, then on success redirect to the builder page (AC2). The modal body is 460px wide, footer has "Cancel" (ghost) + "✓ Create workflow" (accent filled) buttons.

### Anti-Patterns to Avoid

1. **Do NOT fetch data client-side** — all data arrives as Inertia props; use `router.reload({ only: [...] })` for partial reloads after mutations
2. **Do NOT use RTK Query** — this page does not use the RTK Query slice; use `apiFetch` + `router.reload`
3. **Do NOT use MUI components** — fully migrated to Mantine; any MUI import is a regression
4. **Do NOT hardcode route paths** — always use typed route helpers
5. **Do NOT add new `Accordion` for Base Resources** — it moves to its own tab
6. **Do NOT reinvent the triggers side panel without first checking** `WorkflowTriggersDrawer.tsx` — see "WorkflowTriggersDrawer vs new inline panel" note
7. **Do NOT create a separate epic-level feature slice** — co-locate components in `pages/Projects/Workflows/`
8. **Do NOT use a floating modal for Add/Edit trigger** — the design calls for a right-side sliding panel with a scrim, not a centred modal
9. **Do NOT forget to re-render session tags** after any toggle (AUTO, BMAD) or dependency change — the tree nav badges must update in real time without a page reload
10. **Do NOT skip the Expand button** on the Instructions textarea — it is a required UX feature visible in the design
11. **Do NOT omit consequence text** below Skip Policy and On Failure selects — the helper text is part of the design spec

### Key Previous Stories for Context

- **Story 12.10** (`ai/implementation-artifacts/12-10-workflow-builder-page.md`) — original builder page implementation; contains full type definitions (`Step`, `SubStep`, `AssetSpec`, `Workflow`), API hook details, and scope detection logic. Read it before starting.
- **Story 31.2** (`ai/implementation-artifacts/31-2-workflow-builder-base-resources-section-ui.md`) — `BaseResourcesSection.tsx` implementation; Task 7 reuses and moves this component.
- **Story 34.3** (`ai/implementation-artifacts/34-3-frontend-bmad-toggle-in-step-editor.md`) — BMAD toggle in step editor; **subsumed by this story**, implement as part of Behavior section.
- **Story 29.3** (`ai/implementation-artifacts/29-3-workflow-inherit-all-project-resources-flag.md`) — `inheritAllProjectResources` flag on workflow; already serialized; use in Base Resources tab toggle.

### References

- Designer artefact (canonical): `artefacts/aixle-workflows-complete_4_3_7.html`
- GitHub issue: https://github.com/palad-ai/palad-app/issues/212
- Current builder: `app/frontend/pages/Projects/Workflows/BuilderPage.tsx`
- Triggers drawer: `app/frontend/pages/Projects/Workflows/WorkflowTriggersDrawer.tsx`
- Mantine docs: https://mantine.dev/core/tabs/

---

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
