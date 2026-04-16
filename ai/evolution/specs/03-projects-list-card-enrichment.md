# Projects List — Card Enrichment + Sort — Update Specification

> **Scenario:** `ai/evolution/scenarios/03-projects-list-card-enrichment.md`
> **Created:** 2026-04-03
> **Risk:** Low (visual changes + read-only counters, no behavior change)

---

## Change Summary

Enriching project cards with a colored avatar, 4-stat summary row (sessions, workflows, tasks, collaborators), and adding a sort control to the page. Backend: 3 new computed attributes in `ProjectResource` via SQL subselects.

---

## Before

```
┌─────────────────────────────────────────────────────────┐
│  Projects                         [+ Create Project]    │
│  Select a project to view...                            │
│  [🔍 Search projects...]                                │
│                                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐    │
│  │ Project Alpha │ │ Project Beta │ │ Project Gam… │    │
│  │              │ │              │ │              │    │
│  │ Description  │ │ Description  │ │ Description  │    │
│  │ text here... │ │ text here... │ │ text here... │    │
│  │              │ │              │ │              │    │
│  │  3           │ │  1           │ │  0           │    │
│  │  COLLABORATORS│ │  COLLABORATORS│ │  COLLABORATORS│    │
│  │ Last act 2h  │ │ Last act 5d  │ │              │    │
│  └──────────────┘ └──────────────┘ └──────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Problems
1. Card footer dominated by one stat (collaborators) in 20px mono — wastes space, low info density
2. All cards look visually identical — no avatar/icon/color to distinguish at a glance
3. No sessions/workflows/tasks counts — can't gauge project activity without clicking
4. No sort — stuck with alphabetical, can't find recently active project fast

---

## After

```
┌─────────────────────────────────────────────────────────┐
│  Projects                         [+ Create Project]    │
│  Select a project to view...                            │
│  [🔍 Search projects...]    Sort: [Last activity ▾]     │
│                                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐    │
│  │ 🔵P  Project  │ │ 🟢B  Project │ │ 🟠G  Project │    │
│  │     Alpha     │ │     Beta     │ │     Gamma    │    │
│  │              │ │              │ │              │    │
│  │ Description  │ │ Description  │ │ Description  │    │
│  │ text here... │ │ text here... │ │ text here... │    │
│  │              │ │              │ │              │    │
│  │ ⬡ 12  ⚡ 3   │ │ ⬡ 4   ⚡ 1  │ │ ⬡ 0   ⚡ 0  │    │
│  │ ☑ 24  👤 3   │ │ ☑ 8   👤 1  │ │ ☑ 0   👤 0  │    │
│  │ 2h ago       │ │ 5d ago       │ │              │    │
│  └──────────────┘ └──────────────┘ └──────────────┘    │
└─────────────────────────────────────────────────────────┘
```

---

## Components

### 1. `ProjectResource` — Add 3 computed attributes

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

---

### 2. `ProjectsController#index` — Extend SQL subselects

Add 3 subselects to the existing `select()` call:

```ruby
projects = Project.for_user(current_user)
                  .includes(:project_collaborators)
                  .select(
                    "projects.*",
                    "(SELECT MAX(terminal_sessions.started_at) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_last_activity_at",
                    "(SELECT COUNT(*) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_sessions_count",
                    "(SELECT COUNT(*) FROM workflows WHERE workflows.scope_type = 'Project' AND workflows.scope_id = projects.id AND workflows.deleted_at IS NULL) AS cached_workflows_count",
                    "(SELECT COUNT(*) FROM board_tasks INNER JOIN boards ON boards.id = board_tasks.board_id WHERE boards.project_id = projects.id) AS cached_board_tasks_count"
                  )
                  .order(:name)
```

---

### 3. `ProjectCard.tsx` — Redesigned card layout

**Interface update:**
```typescript
interface Project {
  id: number;
  name: string;
  description?: string | null;
  slug: string;
  state: string;
  collaborators_count: number;
  sessions_count: number;
  workflows_count: number;
  board_tasks_count: number;
  last_activity_at?: string | null;
  created_at: string;
}
```

**Avatar:**
- Mantine `Avatar` component, size `md` (38px), `radius="xl"`
- Color from palette: `AVATAR_COLORS[project.id % AVATAR_COLORS.length]`
- Content: first letter of `project.name`, uppercase

```typescript
const AVATAR_COLORS = [
  'blue', 'cyan', 'teal', 'green', 'lime',
  'yellow', 'orange', 'red', 'pink', 'grape',
  'violet', 'indigo',
] as const;
```

**Header row:** `Group` with `Avatar` + `Text` (name), keeping collaborator `Badge` on the right.

**Stat row:** 2×2 grid using `SimpleGrid cols={2}` at the bottom of the card, each stat as:
```tsx
<Group gap={6}>
  <IconTerminal2 size={14} style={{ opacity: 0.5 }} />
  <Text fz={13} c="dimmed">{count}</Text>
</Group>
```

Stats:
| Icon | Label | Field |
|------|-------|-------|
| `IconTerminal2` | sessions | `sessions_count` |
| `IconRoute` | workflows | `workflows_count` |
| `IconSubtask` | tasks | `board_tasks_count` |
| `IconUsers` | members | `collaborators_count` |

**Last activity:** stays at the bottom, `fz={12}`, `c="dimmed"`, same relative formatting.

---

### 4. `ProjectCard.module.css` — New styles

**Add:**
```css
.statsGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 16px;
  width: 100%;
}

.statItem {
  display: flex;
  align-items: center;
  gap: 6px;
}
```

**Remove:** The `20px` mono stat block currently used for collaborators only.

---

### 5. `IndexPage.tsx` — Add sort control

**Sort state:**
```typescript
type SortKey = 'name' | 'last_activity' | 'newest';
const [sortBy, setSortBy] = useState<SortKey>('name');
```

**Sort logic (client-side):**
```typescript
const sortedProjects = useMemo(() => {
  const sorted = [...projects];
  switch (sortBy) {
    case 'last_activity':
      sorted.sort((a, b) => {
        if (!a.last_activity_at && !b.last_activity_at) return 0;
        if (!a.last_activity_at) return 1;
        if (!b.last_activity_at) return -1;
        return new Date(b.last_activity_at).getTime() - new Date(a.last_activity_at).getTime();
      });
      break;
    case 'newest':
      sorted.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
      break;
    case 'name':
    default:
      sorted.sort((a, b) => a.name.localeCompare(b.name));
  }
  return sorted;
}, [projects, sortBy]);
```

Then filter applies on `sortedProjects` instead of `projects`.

**UI:** `Select` component next to the search:
```tsx
<Select
  placeholder="Sort by"
  value={sortBy}
  onChange={(v) => setSortBy((v as SortKey) || 'name')}
  data={[
    { value: 'name', label: 'Name' },
    { value: 'last_activity', label: 'Last activity' },
    { value: 'newest', label: 'Newest first' },
  ]}
  w={180}
  size="sm"
/>
```

---

## Responsive Behavior

| Breakpoint | Behavior |
|-----------|----------|
| Desktop (lg, ≥1200px) | 3-column grid, search + sort in one row |
| Tablet (sm, ≥768px) | 2-column grid, search + sort in one row |
| Mobile (<768px) | 1-column grid, search + sort stack vertically |

Card avatar + stats — always visible, no hiding on mobile.

---

## Files Changed (summary)

| File | Change Type |
|------|-------------|
| `app/resources/project_resource.rb` | Add `sessions_count`, `workflows_count`, `board_tasks_count` |
| `app/controllers/web/company/projects_controller.rb` | Extend `select()` with 3 subselects |
| `app/frontend/pages-inertia/Projects/IndexPage.tsx` | Add sort state + Select + sort logic |
| `app/frontend/pages-inertia/Projects/ProjectCard.tsx` | Avatar + stat grid + updated interface |
| `app/frontend/pages-inertia/Projects/ProjectCard.module.css` | Stats grid styles, remove old stat block |

---

## Acceptance Criteria

| # | Criterion | Test |
|---|-----------|------|
| 1 | Card shows colored avatar with first letter | Visual: each card has a circle with letter, colors differ |
| 2 | Card shows 4 stats: sessions, workflows, tasks, collaborators | Visual: 2×2 grid at card bottom |
| 3 | Stats match actual data | Compare card numbers with project overview page counts |
| 4 | Sort "Name" works | Select Name → alphabetical order |
| 5 | Sort "Last activity" works | Select Last activity → most recently active first |
| 6 | Sort "Newest first" works | Select Newest → most recently created first |
| 7 | Search still works after sort | Sort by activity → type query → filtered results maintain sort |
| 8 | Empty states preserved | Delete all projects → empty state shows; search with no match → no-results state |
| 9 | Create modal still works | Click Create → modal opens, submit → project created |
| 10 | Hover effects preserved | Hover card → blue border + lift + shadow |
| 11 | No N+1 queries | Rails log: single query with subselects, no extra SELECTs per project |
| 12 | Mobile responsive | 375px viewport → 1-column, search + sort stack |

---

## Edge Cases

| Case | Expected |
|------|----------|
| Project with no board (no tasks) | `board_tasks_count: 0` — stat shows "0" |
| Project with no sessions | `sessions_count: 0`, `last_activity_at: null` — stat shows "0", no "Last activity" text |
| Project with soft-deleted workflows | `cached_workflows_count` excludes `deleted_at IS NOT NULL` |
| Very long project name | Truncated with ellipsis (existing behavior via card width) |
| 50+ projects | Client-side sort/filter remain fast (all data loaded at once) |
| `state: archived` projects | Not currently shown (scoped by `for_user`), future: could add gray avatar |
