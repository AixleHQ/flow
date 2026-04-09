# S-03: Projects List — Card Enrichment + Sort

> **Priority:** Medium (UX improvement, minor backend changes)
> **Size:** S
> **Created:** 2026-04-03
> **Analysis source:** `ai/evolution/analysis/page-by-page-evolution.md`, section 4
> **Legacy spec:** `ai/epics/legacy-spa-detailed-spec.md`

---

## Target

Enrich the Projects List page with more contextual information on each card and add sorting. Currently cards show only name, description, a large "Collaborators" number, and last activity — providing little at-a-glance value. After the change, each card shows a project avatar, a compact stat row (sessions / workflows / collaborators), and the list supports sorting by name, last activity, or creation date.

---

## Current State

### What's there (Inertia / Mantine)

1. **`IndexPage.tsx`** (115 LOC) — title + subtitle, "Create Project" button, search field, 3-column `SimpleGrid`, two empty states
2. **`ProjectCard.tsx`** (90 LOC) — name (18px bold), optional collaborator badge, 2-line description, footer with **one** stat: collaborators count in 20px JetBrains Mono + "Last activity X ago"
3. **`ProjectCard.module.css`** — hover: blue border, translateY(-2px), shadow
4. **`CreateProjectModal.tsx`** (68 LOC) — name + description form via Inertia `useForm`
5. **`ProjectResource`** — `id, name, description, slug, state, collaborators_count, last_activity_at, created_at, updated_at`

### What's missing / suboptimal

| # | Gap | Impact |
|---|-----|--------|
| 1 | Card footer dominated by one stat in huge font — low information density | Cards look empty, user must click to learn anything |
| 2 | No visual differentiation between cards — all look identical | Hard to scan when 5+ projects |
| 3 | No sort options — only alphabetical from server | Can't find recently active or newest projects fast |
| 4 | No session/workflow/task counts on card | User can't gauge project activity at a glance |
| 5 | `ProjectResource` doesn't include `sessions_count`, `workflows_count`, `board_tasks_count` | Backend gap |

---

## Desired State

### After changes the user sees:

1. **Project avatar** — colored circle with first letter of project name (color derived from `project.id` hash, consistent per project)
2. **Compact stat row** — 4 stats in a horizontal grid at card bottom:
   - Sessions (icon `IconTerminal2` + count)
   - Workflows (icon `IconRoute` + count)
   - Tasks (icon `IconCheckbox` + count)
   - Collaborators (icon `IconUsers` + count)
3. **Last activity** — relative time stays at very bottom, subtle
4. **Sort control** — `Select` next to search: "Name" (default) / "Last activity" / "Newest first"
5. **No other layout changes** — grid, empty states, create modal stay the same

### Visual Sketch (card)

```
┌─────────────────────────────────┐
│  🔵 A  Project Alpha            │
│                                 │
│  Description text that can be   │
│  up to two lines long and...    │
│                                 │
│  ⬡ 12 sessions  ⚡ 3 workflows │
│  ☑ 24 tasks     👥 4 members   │
│  Last activity 2h ago           │
└─────────────────────────────────┘
```

---

## User Journey

### Entry Point
- User clicks "All Projects" in header or navigates to `/company/projects`
- Server renders `Projects/IndexPage` with project list

### Current Flow
1. Page loads → cards appear in alphabetical grid
2. All cards look the same (white text, dark bg, one number)
3. User must click each card to understand activity level
4. No way to sort — alphabetical only

### Pain Points
- **Low information density**: card has 1 useful stat out of possible 3-4
- **Visual monotony**: no avatar/icon → all cards identical at first glance
- **No sorting**: if 10+ projects, finding the most active requires clicking each

### Proposed Flow
1. Page loads → cards show avatar + stat row → user instantly sees which projects are active
2. User sorts by "Last activity" → most active projects float to top
3. User clicks the right project in one step instead of trial-and-error

---

## Success Criteria

| # | Criterion | How to verify |
|---|-----------|---------------|
| 1 | Each card shows sessions, workflows, tasks, collaborators counts | Visual check — 4 stats visible |
| 2 | Each card has a colored avatar circle with first letter | Visual check — different colors per project |
| 3 | Sort control works (Name / Last activity / Newest) | Click sort → cards reorder |
| 4 | `ProjectResource` returns `sessions_count`, `workflows_count`, `board_tasks_count` | Check JSON props in browser devtools |
| 5 | Performance: no N+1 queries | Check server logs — single query with subselects or counter cache |
| 6 | All existing features preserved | Search, empty states, create modal, hover effects still work |

---

## Scope

### Pages Affected
- `app/frontend/pages-inertia/Projects/IndexPage.tsx`
- `app/frontend/pages-inertia/Projects/ProjectCard.tsx`
- `app/frontend/pages-inertia/Projects/ProjectCard.module.css`

### Components Touched
| Component | Change |
|-----------|--------|
| `IndexPage` | Add sort `Select` next to search, sort logic (client-side on loaded data) |
| `ProjectCard` | Replace single stat footer with avatar + 3-stat row |
| `ProjectCard.module.css` | Avatar styles, stat row layout |
| `ProjectResource` | Add `sessions_count`, `workflows_count` attributes |
| `ProjectsController#index` | Add subselect counts to query |

### Data Changes
- **`ProjectResource`**: add 3 computed attributes (`sessions_count`, `workflows_count`, `board_tasks_count`) via SQL subselects
- **`ProjectsController#index`**: extend `select()` with 3 more subselects (same pattern as `cached_last_activity_at`)
- **No migrations, no new models, no API changes**

### Dependencies
- None new. All within existing Mantine + Tabler Icons.

### Risk Level
**Low** — visual changes + 2 read-only counters. No behavior change. No new dependencies.

---

## Implementation Notes

### ProjectResource additions
```ruby
attribute :sessions_count do |project|
  if project.respond_to?(:cached_sessions_count)
    project.cached_sessions_count
  else
    project.terminal_sessions.count
  end
end

attribute :workflows_count do |project|
  if project.respond_to?(:cached_workflows_count)
    project.cached_workflows_count
  else
    project.workflows.count
  end
end

attribute :board_tasks_count do |project|
  if project.respond_to?(:cached_board_tasks_count)
    project.cached_board_tasks_count
  else
    project.board&.board_tasks&.count || 0
  end
end
```

### Controller query extension
```ruby
.select(
  "projects.*",
  "(SELECT MAX(...)) AS cached_last_activity_at",
  "(SELECT COUNT(*) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_sessions_count",
  "(SELECT COUNT(*) FROM workflows WHERE workflows.scope_type = 'Project' AND workflows.scope_id = projects.id AND workflows.deleted_at IS NULL) AS cached_workflows_count",
  "(SELECT COUNT(*) FROM board_tasks bt INNER JOIN boards b ON b.id = bt.board_id WHERE b.project_id = projects.id) AS cached_board_tasks_count"
)
```

### Avatar color from ID
```typescript
const AVATAR_COLORS = ['blue', 'cyan', 'teal', 'green', 'lime', 'yellow', 'orange', 'red', 'pink', 'grape', 'violet', 'indigo'];
const color = AVATAR_COLORS[project.id % AVATAR_COLORS.length];
```

### Sort (client-side)
```typescript
type SortKey = 'name' | 'last_activity' | 'newest';
// Sort before filter, all data already loaded
```
