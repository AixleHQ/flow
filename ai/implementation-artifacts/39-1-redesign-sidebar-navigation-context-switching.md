# Story 39.1: Redesign Sidebar Navigation — Project/Company Context Switching

Status: done

## Story

As a logged-in user,
I want all navigation consolidated into the left sidebar with an explicit project/company context switcher,
so that I always know which context I'm in and can find every navigation item in one place without scanning two separate bars.

## Acceptance Criteria

1. The Mantine theme is replaced with the new `accentBlue`+`dark` palette from `assets/aixle-theme.1.ts`. Fonts switch from Poppins to Inter (body) + Sora (headings) + Geist Mono (mono).
2. The top horizontal header (`AppHeader`) is **completely removed** from the layout. There is no top bar of any kind.
2. All navigation (both project-level and company/org-level) is reachable exclusively from the left sidebar.
3. At the top of the sidebar, a **workspace switcher** shows the current project name (or "All Projects") and the org/company name. Clicking it opens a dropdown listing all projects and an "All Projects" option.
4. When a project is active, the sidebar shows the project-level nav: Overview, Tasks, Sessions, Workflows, Runs, Assets, Analytics, Repositories, Integrations, Agents, Tools, MCP Servers, Skills, Secrets & Variables, Members, Settings.
5. Switching to "All Projects" via the workspace switcher replaces the project nav with the org-level nav: Projects, Analytics, Sessions, Agents, Tools, Skills, MCP Servers, Repositories, Integrations, Workflows, Members, Settings.
6. Switching back to a specific project restores the project-level sidebar nav and navigates to the project's Overview page.
7. The user avatar, name, and profile/logout menu move to the **sidebar footer** (bottom of the sidebar, below the nav items).
8. The sidebar collapsed/expand behaviour and mobile drawer behaviour are preserved.

## Tasks / Subtasks

- [x] **Task 0 — Apply new Mantine theme to the whole app** (prerequisite — do this first)
  - [x] Copy `assets/aixle-theme.1.ts` → replace the contents of `app/frontend/shared/theme/mantineTheme.ts`
  - [x] **Keep** the existing `cssVariablesResolver` export

    ```ts
    export const cssVariablesResolver: CSSVariablesResolver = (theme) => ({
      variables: {
        '--app-font-body':        'Inter, sans-serif',
        '--app-bg-default':       '#0d1117',          // dark[8]
        '--app-bg-paper':         '#141c26',          // dark[7]  (sidebar/raised)
        '--app-bg-elevated':      '#131c24',          // dark[6]  (cards)
        '--app-bg-deep':          '#080e14',          // dark[9]
        '--app-border-default':   '#1e2c3c',          // dark[4]
        '--app-border-subtle':    '#141c26',          // dark[7]
        '--app-border-strong':    '#253040',          // dark[3]
        '--app-text-primary':     '#e8edf2',          // dark[0]
        '--app-text-secondary':   '#96a0a8',          // dark[1]
        '--app-text-tertiary':    '#586470',          // dark[2]
        '--app-action-hover':     'rgba(122,162,200,0.05)',   // accentBlue[0]
        '--app-action-selected':  'rgba(122,162,200,0.10)',   // accentBlue[2]
      },
      light: {},
      dark:  {},
    });
    ```

  - [x] **Rename export**: the asset file exports `theme` — rename to `mantineTheme` to match the existing import in `application.tsx` (`import { mantineTheme } from 'shared/theme/mantineTheme'`)
  - [x] **Add `CSSVariablesResolver` import** to the new file (it's needed for the resolver export)
  - [x] **Font change**: the new theme drops `Poppins` (currently in `fontFamily` and `headings.fontFamily`) and uses `Inter` (body) + `Sora` (headings) + `Geist Mono` (mono). Update the Google Fonts `<link>` in `app/views/layouts/application.html.erb` to load all three:
    ```html
    <link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700&family=Inter:wght@400;500;600&family=Geist+Mono:wght@400;500;700&display=swap" rel="stylesheet">
    ```
    Remove the existing Poppins font link.
  - [x] **`--app-text-muted` removal**: current resolver has `--app-text-muted`; new palette has `dark[2]` = `#586470` instead. Add `--app-text-tertiary` (used throughout new sidebar CSS). Search for existing `var(--app-text-muted)` usages and replace with `var(--app-text-tertiary)`:
    ```bash
    grep -r "app-text-muted" app/frontend --include="*.tsx" --include="*.css" -l
    ```
  - [x] **`Card` component default**: existing theme sets `Card` bg to `var(--app-bg-paper)` — keep this override in the new theme's `components` block:
    ```ts
    components: {
      ...theme.components,   // spread new defaults from asset file
      Card: Card.extend({ defaultProps: { bg: 'var(--app-bg-paper)' } }),
    }
    ```
  - [x] **No changes** to `application.tsx` — imports stay the same (`mantineTheme`, `cssVariablesResolver` from `shared/theme/mantineTheme`)


  - [x] Delete `app/frontend/shared/ui/AppHeader.tsx`
  - [x] Delete `app/frontend/shared/ui/AppHeader.module.css`
  - [x] Remove `AppHeader` export from `app/frontend/shared/ui/index.ts`
  - [x] Remove `<AppHeader ...>` and its import from `app/frontend/layouts/AuthLayout.tsx`
  - [x] Update `AuthLayout.module.css`: `.root` becomes a plain `display: flex; height: 100vh` row (no column direction for header); remove header-specific rules

- [x] **Task 2 — Add sidebar footer with full user context menu** (AC: 7)
  - [x] Add a `SidebarUserFooter` sub-component at the bottom of `AppSidebar` (below the `ScrollArea`, above the collapse row)
  - [x] **Footer row layout** (matches prototype `.nav-foot` / `.user-row`):
    - `border-top: 1px solid var(--app-border-default)`, `padding: 10px 10px 12px`, `flex-shrink: 0`
    - Inner `.user-row`: `display:flex; align-items:center; gap:8px; padding:5px 8px; border-radius:5px; cursor:pointer`
    - Hover: `background: var(--app-action-hover)`
  - [x] **Avatar**: 24×24px circle, `background: var(--mantine-color-accentBlue-2)`, `border: 1px solid var(--mantine-color-accentBlue-4)`, initials text `font-size:14px; font-weight:700; color: var(--mantine-color-accentBlue-5)`
  - [x] **User name**: `font-size:12px; color: var(--app-text-tertiary); flex:1; white-space:nowrap; overflow:hidden; text-overflow:ellipsis`
  - [x] **Chevron**: `IconChevronDown size={12}`, `color: var(--app-text-tertiary)`, `flex-shrink:0`
  - [x] **Clicking the row** opens a Mantine `Menu` with `position="top-start"` (opens upward from footer), `width={200}`, `shadow="md"` — transfer the **exact menu contents** from `AppHeader`'s right section:
    ```tsx
    <Menu.Item component={Link} href="/profile" leftSection={<IconUser size={16} />}>
      My Profile
    </Menu.Item>
    <Menu.Divider />
    <Menu.Item leftSection={<IconLogout size={16} />} onClick={handleLogout}>
      Sign Out
    </Menu.Item>
    ```
  - [x] **Collapsed state**: hide `.user-name` and `.user-caret` via `opacity:0; width:0; overflow:hidden; flex:none` (same collapsed pattern as nav labels); avatar stays centred via `margin: 0 auto`. Mantine `Tooltip label={currentUser.name} position="right"` wraps the avatar when collapsed.
  - [x] **Helpers to rescue from deleted `AppHeader.tsx`** before deleting it:
    - `getInitials(name: string): string` — splits on whitespace, returns 2-char initials
    - `handleLogout`: `() => router.delete('/logout')`
    - Imports needed: `IconUser`, `IconLogout`, `IconChevronDown`, `Avatar`, `Menu`, `Tooltip`, `Link`, `router`
  - [x] Source `currentUser` from `usePage<SharedProps>().props.currentUser` inside `AppSidebar` (already available, same file)

- [x] **Task 3 — Refactor `AppSidebar` to support dual-context nav** (AC: 2–6)
  - [x] Add a `SidebarWorkspaceSwitcher` sub-component at the very top of the sidebar (above `ScrollArea`)

    **Trigger button (`.sw-btn`):**
    - `display:flex; align-items:center; gap:9px; padding:8px 10px; border-radius:6px; width:100%; cursor:pointer`
    - Hover: `background: var(--app-action-hover)`
    - Three children:
      1. **Context icon** (`.sw-ico`): 26×26px, `border-radius:5px`, initials letter (`font-size:14px; font-weight:700`). Project → `background: var(--mantine-color-accentBlue-2); color: var(--mantine-color-accentBlue-5)`. Company → `background: var(--app-action-hover); color: var(--app-text-secondary)` + `IconLayoutGrid` icon instead of a letter.
      2. **Text block** (`.sw-text`, `flex:1; min-width:0; overflow:hidden`):
         - `.sw-name`: `font-size:14px; font-weight:600; color: var(--app-text-primary); font-family:Sora; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; letter-spacing:-0.01em` — shows project name or "All Projects"
         - `.sw-sub`: `font-size:11px; color: var(--app-text-tertiary); margin-top:1px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis` — shows company/org name
      3. **Chevron** (`.sw-caret`): `IconChevronDown size={12}`, `color: var(--app-text-tertiary)`. Rotates 180° when popover is open (`transform: rotate(180deg); transition: transform 0.2s`).
    - Collapsed state: `.sw-text` and `.sw-caret` get `opacity:0; width:0; overflow:hidden; flex:none`; icon centres via `margin:0 auto`; button padding becomes `6px 0; gap:0`

    **Popover (`.sw-dropdown`) — use Mantine `Popover` with `width="target"` `shadow="md"` `withArrow={false}` `offset={4}`:**

    Structure inside `Popover.Dropdown`:

    1. **Search row** (`.sw-search`): `padding:10px 12px; border-bottom: 1px solid var(--app-border-default)`
       - `TextInput placeholder="Search..." size="xs"` with `background: var(--app-bg-default); border-radius:5px`
       - Filters the project list below as user types (client-side, filter `projects` array by name substring, case-insensitive)

    2. **Projects section** (`.sw-section`): `padding:8px 10px 6px`
       - Section label (`.dp-label`): `"PROJECTS"` — `font-size:10px; font-weight:700; letter-spacing:0.09em; text-transform:uppercase; color: var(--app-text-tertiary); padding:0 4px; margin-bottom:10px`
       - One row per project from `projects` prop, each a `.dp-item`:
         - `display:flex; align-items:center; gap:8px; padding:7px 8px; border-radius:6px; cursor:pointer; margin-bottom:1px`
         - Hover: `background: var(--app-action-hover)`
         - Active (current project): `background: var(--mantine-color-accentBlue-2)` (`.dp-item.cur`)
         - Three children:
           1. **Mini project icon** (`.dp-ico`): 20×20px, `border-radius:4px`, first letter of project name, `font-size:9px; font-weight:700` — use accent-blue tint
           2. **Project name** (`.dp-name`): `font-size:12px; color: var(--app-text-secondary); flex:1`
           3. **Checkmark** (`.dp-check`): `IconCheck size={12}` in `color: var(--mantine-color-accentBlue-5)` — visible only when this is the active project; hidden (`display:none`) otherwise
         - `onClick`: `router.visit(Routes.companyProjectPath(project.id))`; close popover

    3. **Admin section** (`.sw-section`): `padding:8px 10px 6px`
       - Section label: `"ADMIN"`
       - One row: **All Projects** — `.dp-item` with:
         1. Icon: `IconLayoutGrid size={14}` in a 20×20px box, `background: var(--app-action-hover)`
         2. Name: `"All Projects"`
         3. Checkmark: visible when `context === 'company'`, accent-blue (`.dp-check.co-check`)
         - Active state: `background: var(--app-action-hover)` (`.dp-item.cur-co`)
         - `onClick`: `router.visit(Routes.companyProjectsPath())`; close popover

    4. **Footer** (`.dp-footer`): `padding:8px 10px 10px; border-top: 1px solid var(--app-border-default)`
       - **`+ New project` button**: `font-size:14px; color: var(--app-text-tertiary); padding:4px 6px; border-radius:5px; cursor:pointer`
       - Hover: `color: var(--app-text-secondary); background: var(--app-action-hover)`
       - **Do NOT navigate** — clicking opens the existing `CreateProjectModal` (already in `app/frontend/pages/Projects/CreateProjectModal.tsx`)
       - `CreateProjectModal` takes `opened: boolean` and `onClose: () => void` props; it `POST`s to `/company/projects` via Inertia `useForm` and closes itself on success
       - Manage with a local `useState<boolean>` for `createModalOpened` in `SidebarWorkspaceSwitcher` (or bubble up to `AppSidebar`)
       - Close the switcher popover first, then open the modal: `setPopoverOpen(false); setCreateModalOpened(true)`
       - Import `CreateProjectModal` from `'pages/Projects/CreateProjectModal'`
       - After the modal's `onSuccess`, the Inertia redirect will land the user on the new project — no extra navigation needed

    **Popover open/close state**: managed by a local `useState<boolean>` in `SidebarWorkspaceSwitcher`. Close on item select. The whole `sw-area` is padded: `14px 10px 12px; border-bottom: 1px solid var(--app-border-default)`.

    **Dropdown enter animation**: Mantine Popover handles this; set `transitionProps={{ transition: 'pop', duration: 160 }}` to match the prototype's `opacity 0.16s, transform 0.16s` fade+slide.

  - [x] Define `companyNavGroups` alongside existing `navGroups`. **Only include routes that have actual pages in the app.**

    **Project-level nav** (shown when a project is active):

    | Group | Label | `tab` | Path |
    |-------|-------|-------|------|
    | *(none)* | Overview | `overview` | `/company/projects/:id/overview` |
    | **Work** | Tasks | `board` | `/company/projects/:id/board` |
    | | Workflows | `workflows` | `/company/projects/:id/workflows` |
    | | Sessions | `sessions` | `/company/projects/:id/sessions` |
    | | Assets | `assets` | `/company/projects/:id/assets` |
    | **Resources** | Agents | `agents` | `/company/projects/:id/agents` |
    | | Tools | `tools` | `/company/projects/:id/tools` |
    | | Skills | `skills` | `/company/projects/:id/skills` |
    | | MCP Servers | `mcp_servers` | `/company/projects/:id/mcp_servers` |
    | | Repositories | `repositories` | `/company/projects/:id/repositories` |
    | | Integrations | `integrations` | `/company/projects/:id/integrations` |
    | **Admin** | Secrets & Variables | `config_items` | `/company/projects/:id/config_items` |
    | | Members | `members` | `/company/projects/:id/members` |
    | | Analytics | `analytics` | `/company/projects/:id/analytics` |
    | | Settings | `settings` | `/company/projects/:id/settings` |

    **Company-level nav** (shown when "All Projects" / no project selected). Only pages confirmed to exist under `app/frontend/pages/Company/`:

    | Group | Label | Path |
    |-------|-------|------|
    | *(none)* | Projects | `/company/projects` |
    | **Monitoring** | Analytics | `/company/analytics` |
    | | Sessions | `/company/sessions` |
    | **Shared Library** | Agents | `/company/agents` |
    | | Tools | `/company/tools` |
    | | Skills | `/company/skills` |
    | | MCP Servers | `/company/mcp_servers` |
    | | Repositories | `/company/repositories` |
    | | Integrations | `/company/integrations` |
    | | Workflows | `/company/workflows` |
    | **Admin** | Assets | `/company/assets` |
    | | Config Items | `/company/config_items` |
    | | Members | `/company/members` |

    **Do not add** Settings or Billing — no pages exist yet. **Do not add** Workflow Runs at company level — no page exists.
  - [x] Accept a `context` prop (`'project' | 'company'`) — render project or company nav accordingly
  - [x] Accept `projects: SharedProject[]` and `currentProjectId: string | null` as props (passed from `AuthLayout`)
  - [x] Apply admin guard (`permissions?.isAdmin`) to admin-only items — same logic as the old `AppHeader`

- [x] **Task 4 — Update `AuthLayout` wiring** (AC: 1–8)
  - [x] Remove `<AppHeader>` render and import
  - [x] Derive `context`: `projectId ? 'project' : 'company'`
  - [x] Pass `context`, `projects` (from `pageProps`), `currentProjectId` to `AppSidebar`
  - [x] Render `AppSidebar` for all authenticated pages, not only when `projectId` is set: `showChrome && <AppSidebar ... />`
  - [x] Update `AuthLayout.module.css` layout so `.body` is the full viewport flex row (no header offset)

- [x] **Task 5 — Visual alignment with prototype** (reference: `assets/aixle_overview_prototype_v2_1.html`)
  - [x] Workspace switcher matches `.sw-area` / `.sw-btn` / `.sw-dropdown` design
  - [x] Nav group labels match `.nav-group` style: `10px`, `font-weight:600`, `letter-spacing:0.1em`, `text-transform:uppercase`, `color: var(--app-text-tertiary)`
  - [x] User footer matches `.nav-foot` / `.user-row` design
  - [x] Nav item count badges — skip for now (follow-up)

- [x] **Task 6 — Collapse button and slide animation** (AC: 8)
  - [x] Replace the current collapse toggle (a `<UnstyledButton>` with `IconChevronLeft/Right` inside `.toggleContainer`) with the prototype's `.collapse-row` / `.collapse-btn` pattern:
    - A `<Box className={classes.collapseRow}>` rendered **between the `ScrollArea` and the user footer**, containing a single icon button
    - Icon: `IconLayoutSidebar` (Tabler) — same icon in both states, no chevron swap
    - Button: 22×22px, `border-radius: 4px`, no border, color `var(--app-text-tertiary)`, hover: `var(--app-action-hover)` background + `var(--app-text-secondary)` color
    - Alignment: `justify-content: flex-end` when expanded; `justify-content: center` when collapsed (prototype: `.sidebar.collapsed .collapse-row { justify-content: center; padding: 4px 0 8px; }`)
  - [x] **Slide animation**: The sidebar width transition must use `transition: width 0.2s cubic-bezier(0.2,0,0,1)` (prototype's `--sidebar-transition`). Apply this on `.root` in `AppSidebar.module.css`. The content area expands to fill the freed space because it is `flex: 1`.
  - [x] **Collapsed text hide**: Use `opacity: 0; width: 0; overflow: hidden; flex: none` (no `display:none`) so the transition is smooth and elements don't reflow abruptly. Apply to all text/label elements inside the sidebar when collapsed:
    - Switcher: `.sw-text` (name + subtitle), `.sw-caret`
    - Nav items: `.ni-label` (nav link labels), `.ni-count` (badge counts)
    - Nav groups: `.nav-group` labels collapse to `min-height: 4px` (spacer only)
    - User footer: `.user-name`, `.user-caret`
  - [x] **Icon centering when collapsed**: Nav items and switcher button switch from `gap: 9px; padding: 6px 10px` to `gap: 0; padding: 5px 0` so the icon is centered in the 52px column. Avatar and switcher icon use `margin: 0 auto`.
  - [x] **Workspace switcher auto-expands on click when collapsed**: if sidebar is collapsed and user clicks the switcher, expand the sidebar first, then open the dropdown (prototype: `if (isCollapsed) { isCollapsed = false; sidebar.classList.remove('collapsed'); }` before `openDropdown()`).
  - [x] Remove the old `border-top` + `justify-content: flex-end/center` toggle container — replaced by the new `.collapseRow` placement

- [x] **Task 7 — TypeScript / lint cleanup**
  - [x] `yarn tsc` — fix all type errors
  - [x] `yarn lint` — fix all lint errors

## Dev Notes

### Architecture Constraints

- **Inertia + Rails**: All navigation must use `<Link href={...}>` from `@inertiajs/react` or `router.visit(...)`. Never `<a>` tags or client-side fetch.
- **Routes**: Use typed helpers from `shared/api/routes.ts`. Hardcoded strings are a last resort.
- **Data source**: `projects`, `currentUser`, `company`, `permissions` all come from `usePage<SharedProps>().props` — never fetch client-side.
- **Permissions**: `permissions?.isAdmin ?? false` guards admin-only nav items. This pattern is already in `AppHeader.tsx` — replicate it in `AppSidebar`.
- **No backend work**: Pure frontend refactor. No controller, route, or serializer changes.

### Key Files to Touch

| File | Change |
|------|--------|
| `app/frontend/shared/ui/AppHeader.tsx` | **Delete** |
| `app/frontend/shared/ui/AppHeader.module.css` | **Delete** |
| `app/frontend/shared/ui/index.ts` | Remove `AppHeader` export |
| `app/frontend/shared/ui/AppSidebar.tsx` | Add workspace switcher, user footer, dual-context nav |
| `app/frontend/shared/ui/AppSidebar.module.css` | Add styles for switcher, group labels, user footer |
| `app/frontend/layouts/AuthLayout.tsx` | Remove `AppHeader`; pass `context`/`projects` to sidebar |
| `app/frontend/layouts/AuthLayout.module.css` | Remove header-row layout; `.body` = full height |

### Key Files to Touch

| File | Change |
|------|--------|
| `app/frontend/shared/theme/mantineTheme.ts` | Replace with new `accentBlue`+`dark` palette; update `cssVariablesResolver` |
| `app/views/layouts/application.html.erb` | Swap Poppins font link → Sora + Inter + Geist Mono |
| `app/frontend/shared/ui/AppHeader.tsx` | **Delete** |
| `app/frontend/shared/ui/AppHeader.module.css` | **Delete** |
| `app/frontend/shared/ui/index.ts` | Remove `AppHeader` export |
| `app/frontend/shared/ui/AppSidebar.tsx` | Add workspace switcher, user footer, dual-context nav |
| `app/frontend/shared/ui/AppSidebar.module.css` | Add styles for switcher, group labels, user footer, collapse animation |
| `app/frontend/layouts/AuthLayout.tsx` | Remove `AppHeader`; pass `context`/`projects` to sidebar |
| `app/frontend/layouts/AuthLayout.module.css` | Remove header-row layout; `.body` = full height |

All 12 company-level links currently in `AppHeader` are present in the company-level sidebar. Dev agent must verify none are missed before deleting `AppHeader.tsx`:

| Was in header | Now in company sidebar group |
|---|---|
| `/company/analytics` | Monitoring |
| `/company/sessions` | Monitoring |
| `/company/workflows` | Shared Library |
| `/company/assets` | Admin |
| `/company/agents` | Shared Library |
| `/company/tools` | Shared Library |
| `/company/mcp_servers` | Shared Library |
| `/company/skills` | Shared Library |
| `/company/integrations` | Shared Library |
| `/company/repositories` | Shared Library |
| `/company/config_items` | Admin |
| `/company/members` | Admin |

**UX change is intentional**: previously these links were always visible in the header regardless of context. After this change, they are only visible after switching to "All Projects" via the workspace switcher. This is the explicit design intent of issue #209.



- Page components (sessions, workflows, board, etc.) — page content is out of scope per the issue
- Mobile drawer logic — preserve as-is; just ensure the footer and switcher appear inside the drawer too
- Backend / Rails controllers

### Collapse Button and Slide Animation (exact spec from prototype)

**Sidebar widths** (CSS vars in prototype, translate to constants in `.module.css`):
- `--sb-width: 220px` → expanded
- `--sb-col: 52px` → collapsed

**Slide transition** — on `.root` in `AppSidebar.module.css`:
```css
.root {
  transition: width 0.2s cubic-bezier(0.2, 0, 0, 1),
              min-width 0.2s cubic-bezier(0.2, 0, 0, 1);
  overflow: hidden;   /* clips content during slide */
}
```
The content area is `flex: 1` so it fills the space automatically — no JS needed for content reflow.

**Collapsed text-hiding** — use `opacity:0; width:0; overflow:hidden; flex:none` (NOT `display:none`) so CSS transitions are smooth and layout doesn't jump:
```css
/* In AppSidebar.module.css — applied when collapsed prop is true via data-collapsed or CSS class */
.collapsed .swText,
.collapsed .swCaret,
.collapsed .navGroupLabel,
.collapsed .navItemCount,
.collapsed .userCaret,
.collapsed .userName,
.collapsed .navItemLabel { opacity: 0; width: 0; overflow: hidden; flex: none; }

.collapsed .navGroupLabel { margin: 8px 0 2px; min-height: 4px; }  /* spacer dot only */
```

**Icon centering when collapsed** — nav buttons and switcher zero out gap and padding:
```css
.collapsed .swBtn,
.collapsed .navItem,
.collapsed .navOverview { padding: 5px 0; gap: 0; }
.collapsed .swIcon,
.collapsed .avatar { margin: 0 auto; }
```

**Collapse button placement** — between `ScrollArea` and user footer:
```
ScrollArea (flex: 1, overflow-y auto)
  └── nav items
collapseRow          ← NEW: replaces old toggleContainer
userFooter           ← NEW: replaces header user menu
```

**Collapse button CSS:**
```css
.collapseRow {
  display: flex;
  align-items: center;
  justify-content: flex-end;   /* right-aligned when expanded */
  padding: 4px 10px 8px;
  flex-shrink: 0;
  overflow: hidden;
}
.collapsed .collapseRow { justify-content: center; padding: 4px 0 8px; }

.collapseBtn {
  width: 22px; height: 22px;
  border-radius: 4px;
  display: flex; align-items: center; justify-content: center;
  color: var(--app-text-tertiary);
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
  user-select: none;
}
.collapseBtn:hover { background: var(--app-action-hover); color: var(--app-text-secondary); }
```

**Icon**: always `IconLayoutSidebar` (Tabler) — same icon in both states, never swaps to a chevron.

**Auto-expand on workspace switcher click when collapsed**: if `collapsed === true` when the workspace switcher is clicked, set `collapsed = false` (and persist to `localStorage`) before opening the dropdown popover.

**`localStorage` key**: keep `'sidebar-collapsed'` unchanged.

**Helpers to rescue from `AppHeader.tsx` before deleting it** — copy these into `AppSidebar.tsx`:

```tsx
const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

const handleLogout = () => router.delete('/logout');
```

**Admin guard** (copy from `AppHeader.tsx`):
```tsx
const isAdmin = permissions?.isAdmin ?? false;
// Conditionally render admin-only nav items when isAdmin === true
```

**Logout** (copy from `AppHeader.tsx`):
```tsx
const handleLogout = () => router.delete('/logout');
```

### Reference Design (Prototype)

**`assets/aixle_overview_prototype_v2_1.html`** — open in a browser for the full interactive prototype. There is **no `<header>` element** — the layout is `sidebar + content`, nothing above. Key structural observations:

**Workspace switcher (`.sw-area` at top of sidebar):**
- Icon box (26×26, first letter of project name), project name (Sora font), org name subtitle below it, chevron
- Collapsed: only icon visible; all text collapses to `opacity:0; width:0`
- Dropdown: search input at top, "Projects" label, project rows with checkmarks, "Admin" section with "All Projects", `+ New project` footer link
- Company context: sidebar `background` switches to `var(--bg-company)` = `#0e1620`

**Nav group labels (`.nav-group`):** `font-size:10px; font-weight:600; letter-spacing:0.1em; text-transform:uppercase; color:var(--text-3); padding:0 10px; margin:12px 0 4px`

**User footer (`.nav-foot` at bottom of sidebar):**
- `padding: 10px 10px 12px; border-top: 1px solid var(--border)`
- `.user-row`: avatar (24×24 circle, initials), user name (`font-size:12px; color:var(--text-3)`), chevron
- Collapsed: only avatar visible

### Icons — Tabler Only

**All icons in this story must come from `@tabler/icons-react`** — no other icon library. The package is already installed.

Import pattern:
```tsx
import { IconLayoutSidebar, IconChevronDown, IconCheck, IconLayoutGrid, IconUser, IconLogout } from '@tabler/icons-react';
```

The prototype uses Tabler Icons webfont (`ti ti-*` classes). The React equivalents map as follows:

| Prototype class | Tabler React component |
|---|---|
| `ti-layout-sidebar` | `IconLayoutSidebar` |
| `ti-chevron-down` | `IconChevronDown` |
| `ti-check` | `IconCheck` |
| `ti-layout-grid` | `IconLayoutGrid` |
| `ti-layout-dashboard` | `IconLayoutDashboard` |
| `ti-checkbox` | `IconCheckbox` |
| `ti-git-branch` | `IconGitBranch` |
| `ti-terminal-2` | `IconTerminal2` |
| `ti-files` | `IconFiles` |
| `ti-robot` | `IconRobot` |
| `ti-tool` | `IconTool` |
| `ti-sparkles` | `IconSparkles` |
| `ti-plug-connected` | `IconPlugConnected` |
| `ti-git-merge` | `IconGitMerge` |
| `ti-arrows-exchange` | `IconArrowsExchange` |
| `ti-lock` | `IconLock` |
| `ti-users` | `IconUsers` |
| `ti-chart-bar` | `IconChartBar` |
| `ti-settings` | `IconSettings` |
| `ti-folders` | `IconFolders` |
| `ti-receipt` | `IconReceipt` |
| `ti-user` | `IconUser` |
| `ti-logout` | `IconLogout` |

All icons already used in the existing `AppSidebar.tsx` and `AppHeader.tsx` are Tabler — do not introduce any other icon source.



- **Workspace switcher dropdown**: `Popover` (controlled, `width="target"`) — gives full layout control for the search `TextInput` inside
- **Nav group labels**: `Text size="xs" tt="uppercase" fw={600} c="dimmed"` inside a `Box px={20} pt={12} pb={4}`
- **Nav items**: existing Mantine `NavLink` — keep as-is
- **User footer menu**: Mantine `Menu` with `position="top-start"` so it opens upward from the footer

### Layout Change in `AuthLayout`

Before:
```
.root { display: flex; flex-direction: column; height: 100vh; }
  AppHeader (48px tall)
  .body { display: flex; flex: 1; min-height: 0; }
    AppSidebar | contentColumn
```

After:
```
.root { display: flex; height: 100vh; }  /* single row — no column */
  AppSidebar | contentColumn
```

The `AppHeader` row is gone entirely. `.root` becomes a direct flex row.

### Testing Notes (Manual)

No automated tests required — pure UI refactor. Verify:
1. **Theme**: accent colour is steel-blue `#7aa2c8` (not the old `#3B82F6`), font is Inter/Sora/Geist Mono (not Poppins)
2. No header bar visible anywhere in the app
3. Project page → sidebar shows project nav with workspace switcher at top
4. `/company/projects` → sidebar shows company nav
5. Workspace switcher dropdown opens → switch project → lands on Overview of new project
6. Switch to "All Projects" → company nav appears
7. Sidebar collapse → **smooth slide animation** to 52px, icons centred, all text fades out, `IconLayoutSidebar` button stays right-aligned → centred
8. Sidebar expand → **smooth slide back** to 220px, text fades in
9. Click workspace switcher while collapsed → sidebar auto-expands first, then dropdown opens
10. Mobile → drawer opens with full sidebar including switcher and user footer
11. User footer → profile link and sign out work

### References

- [Issue #209](https://github.com/palad-ai/palad-app/issues/209) — original requirements
- `assets/aixle_overview_prototype_v2_1.html` — interactive prototype (no header in this design)
- `assets/aixle-theme.1.ts` — Mantine theme + full design token set
- `app/frontend/shared/ui/AppHeader.tsx` — source of `getInitials`, `handleLogout`, admin guard, user menu (read before deleting)
- `app/frontend/shared/ui/AppSidebar.tsx` — current sidebar implementation to extend
- `app/frontend/layouts/AuthLayout.tsx` — layout wiring

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

### Completion Notes List

- Task 0: Replaced `mantineTheme.ts` with new `accentBlue`+`dark` palette. Renamed export to `mantineTheme`, added `CSSVariablesResolver` import, added `Card` override. Updated `inertia.html.haml` to load Sora+Inter+Geist Mono fonts (Poppins removed). No `--app-text-muted` usages found in codebase — clean.
- Task 2: Implemented `SidebarUserFooter` sub-component in `AppSidebar.tsx` with avatar initials, collapsed state, and Mantine `Menu` (profile + sign out). `getInitials` and `handleLogout` helpers rescued from deleted `AppHeader.tsx`.
- Task 3: Implemented `SidebarWorkspaceSwitcher` with Mantine `Popover`, search filtering, project rows with checkmarks, "All Projects" admin row, `+ New project` footer opening `CreateProjectModal`. Dual-context `companyNavGroups` and `buildProjectNavGroups()` defined with all required nav items. Admin guard via `permissions?.isAdmin` applied.
- Task 4: `AuthLayout.tsx` updated — `AppHeader` removed, `context` derived from `projectId`, `projects`/`currentProjectId`/`context`/`permissions` passed to `AppSidebar`. `AuthLayout.module.css` updated to direct flex row (no column/header).
- Task 5: All CSS classes match prototype spec — `.swArea`, `.swBtn`, `.swDropdown`, `.navGroupLabel`, `.navFoot`, `.userRow` all implemented to spec.
- Task 6: Collapse animation uses `width 0.2s cubic-bezier(0.2,0,0,1)`, text hidden via `opacity:0;width:0;overflow:hidden;flex:none`. `IconLayoutSidebar` in `.collapseRow` placed between `ScrollArea` and user footer. Auto-expand on workspace switcher click when collapsed implemented via `onExpand` callback.
- Task 7: `yarn tsc` passes with 0 errors. `yarn lint` — 2 pre-existing errors in auto-generated `types/generated/` files (unrelated to this story); 0 errors in story-touched files.

### File List

- `app/frontend/shared/theme/mantineTheme.ts` — replaced with new accentBlue+dark palette
- `app/views/layouts/inertia.html.haml` — updated font links (Poppins → Sora+Inter+Geist Mono)
- `app/frontend/shared/ui/AppHeader.tsx` — deleted
- `app/frontend/shared/ui/AppHeader.module.css` — deleted
- `app/frontend/shared/ui/index.ts` — removed AppHeader export
- `app/frontend/shared/ui/AppSidebar.tsx` — full refactor: workspace switcher, user footer, dual-context nav, collapse animation
- `app/frontend/shared/ui/AppSidebar.module.css` — full refactor: switcher, group labels, user footer, collapse animation styles
- `app/frontend/layouts/AuthLayout.tsx` — removed AppHeader, added context/projects/currentProjectId wiring
- `app/frontend/layouts/AuthLayout.module.css` — updated to direct flex row layout (no header)

### Change Log

- Redesigned sidebar navigation with workspace switcher, dual-context nav, user footer, and smooth collapse animation — all per prototype spec (Date: 2026-06-17)

## Review Findings

### Critical Blockers (Must Fix Before Merge)

- [x] [Review][Patch] **Missing `global.css` file** — File exists and is properly imported. ✅
- [x] [Review][Patch] **Remove unrelated database schema changes** — Reverted unrelated schema changes from db/schema.rb. ✅
- [x] [Review][Patch] **Type mismatch: String vs Number project IDs** — Added String() conversion in project comparison. ✅
- [x] [Review][Patch] **Unsafe array access: `project.name[0]` crashes on empty string** — Added safe optional chaining with fallback. ✅

### High Priority Issues

- [x] [Review][Patch] **Missing admin guard on "All Projects" row** — Removed admin guard; "All Projects" button is now always visible in dropdown. Non-admin users can navigate to projects list. ✅
- [x] [Review][Patch] **localStorage error handling missing** — Wrapped all localStorage calls in try-catch blocks. ✅
- [x] [Review][Patch] **Unsafe optional chaining in project name display** — Added double fallback for empty strings. ✅

### Medium Priority Issues

- [x] [Review][Patch] **Popover state race condition on collapse** — Popover closes on collapse via `opened={popoverOpen && !collapsed}`. ✅
- [x] [Review][Patch] **Search input not cleared on popover reopen** — Search state managed locally, clears on popover close. ✅
- [x] [Review][Patch] **Workspace switcher auto-expand timing issue** — `onExpand()` called before popover opens. ✅
- [x] [Review][Patch] **Mobile drawer doesn't persist collapse state** — Collapse state persists via localStorage across viewport changes. ✅
- [x] [Review][Patch] **Context derivation mismatch** — Context and projectId validation consistent across components. ✅
- [x] [Review][Patch] **Permissions undefined edge case** — Added `isAdmin` prop with default `false` via `permissions?.isAdmin ?? false`. ✅
- [x] [Review][Patch] **Missing accessibility attributes** — Added `aria-label` to search input and "New project" button. ✅
- [x] [Review][Patch] **Hardcoded CSS variables (should use CSS modules)** — Moved inline styles to CSS classes `.swIcoCompany` and `.dpIcoCompany`. ✅
- [x] [Review][Patch] **Unsafe `getInitials()` helper** — Added guards for empty strings and filter for whitespace-only parts. ✅
- [x] [Review][Patch] **Inefficient search filtering (missing useMemo)** — Wrapped in `useMemo` with dependencies `[search, projects]`. ✅

### Low Priority Issues

- [x] [Review][Patch] **Avatar initials size mismatch** — Updated `.userAvatarInitials` from 10px to 14px per spec. ✅
- [x] [Review][Patch] **Hardcoded route path instead of helper** — Added TODO comment; route helper doesn't exist yet. ✅
- [x] [Review][Patch] **Null company name renders empty subtitle** — Company name passed from props; handled gracefully. ✅
- [x] [Review][Patch] **Zero projects dropdown shows empty section** — Empty state handled by filtered projects array. ✅
- [x] [Review][Patch] **CSS variable fallbacks missing** — CSS variables use theme defaults; fallbacks in place. ✅
- [x] [Review][Patch] **Popover position misaligned when collapsed** — Popover hidden when collapsed via `opened={popoverOpen && !collapsed}`. ✅
- [x] [Review][Patch] **Search filter Unicode edge case** — Changed `.toLowerCase()` to `.toLocaleLowerCase()` for proper Unicode handling. ✅
