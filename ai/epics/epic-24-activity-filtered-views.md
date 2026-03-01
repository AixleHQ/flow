# Epic 24: Activity Feed & Filtered Views (Post-MVP)

> Activity feed at board and task level, and filtered board views via Ransack.

**Phase:** 15 (Post-MVP. Depends on: Epic 20-23 complete)

**PRD:** [Board & Tasks PRD](../prd/board-tasks.md)

**User Outcome:** Users see an activity feed showing what happened on the board (task moves, comments, workflow events) with actor attribution. Users can filter the board by assignee, type, tags, and priority, and save named filter presets.

**FRs Covered:** FR46, FR47, FR48, FR49, FR50, FR51

---

## Stories

### Story 24.1: Activity Event Model

**As a** system,
**I want** to record board activity events,
**So that** users and PMs can track what's happening on the board.

**Acceptance Criteria:**
- Migration creates `board_activities` table:
  - `id`, `board_id` (references, not null)
  - `board_task_id` (references, nullable)
  - `event_type` (string, not null) — `task_moved`, `task_created`, `task_updated`, `comment_added`, `asset_attached`, `workflow_started`, `workflow_completed`, `workflow_failed`, `human_help_requested`
  - `actor_id` (references users, not null)
  - `actor_type` (string, not null) — `human`, `agent`, `system`
  - `metadata` (jsonb, default: {}) — event-specific data
  - `created_at` (timestamp, not null)
- `BoardActivity` model — append-only
- Created automatically from `TaskMoveService`, comment creation, asset upload, workflow events
- `metadata` examples:
  - `task_moved`: `{ from_column: "Backlog", to_column: "Tech Design", trigger: "auto" }`
  - `comment_added`: `{ tag: "tech_design", preview: "First 100 chars..." }`
  - `workflow_started`: `{ workflow_name: "Create Tech Design", workflow_run_id: 123 }`

**Technical notes:**
- No `updated_at` — activities are immutable events
- `metadata` is jsonb for flexibility — different event types store different data
- Actor attribution format: "agent (managed by [User Name])" — resolved in serializer

---

### Story 24.2: Board Activity Feed API & UI

**As a** user,
**I want** to view an activity feed showing what happened on the board,
**So that** I can track progress and understand what agents and teammates are doing.

**Acceptance Criteria:**
- API: `GET /board/activities` — paginated, newest first
- API: `GET /tasks/:task_id/activities` — task-level feed
- Filters: `event_type`, `actor_type`, `since` (timestamp)
- Serializer: `BoardActivitySerializer` with human-readable `description` field
  - Format: "Agent (managed by Artem) moved 'Login API' from Tech Design to Implementation"
  - Format: "Katya added comment with tag 'feedback' on 'Login API'"
- Frontend: activity feed panel on board page (sidebar or bottom panel)
- Task detail sidebar: activity tab showing task-specific events

**Technical notes:**
- Pagination: cursor-based using `created_at` + `id` (keyset pagination)
- Description generated in serializer from event_type + metadata — not stored
- Feed updates via ActionCable: new activities broadcast and prepended to feed

---

### Story 24.3: Filtered Board Views

**As a** user,
**I want** to filter the board by assignee, type, tags, and priority,
**So that** I can focus on relevant tasks when the board has many items.

**Acceptance Criteria:**
- Board API supports Ransack filters on tasks:
  - `assignee_id_eq`, `task_type_eq`, `priority_eq`
  - `tags_contains` (any of specified tags)
  - `title_cont` (search)
- Frontend: filter bar above board columns
- Filter controls: assignee dropdown, type dropdown, priority dropdown, tag multi-select, search input
- Filtered view: columns still show, but only matching tasks visible
- Empty columns with no matching tasks show "No matching tasks"
- Clear filters button

**Technical notes:**
- Ransack already used in other parts of the app
- Filter params passed as query parameters: `GET /board?q[assignee_id_eq]=1&q[task_type_eq]=story`
- Frontend manages filter state in URL params (shareable filtered views)

---

### Story 24.4: Saved Filter Presets

**As a** user,
**I want** to save named filter presets,
**So that** I can quickly switch between views like "my work" or "all bugs".

**Acceptance Criteria:**
- Migration creates `board_view_presets` table:
  - `id`, `board_id` (references, not null)
  - `name` (string, not null)
  - `filters` (jsonb, not null) — Ransack filter params
  - `user_id` (references, not null) — creator
  - `shared` (boolean, default: false) — visible to all project members
  - `timestamps`
- CRUD API: `POST/GET/DELETE /board/view_presets`
- Frontend: preset selector dropdown in filter bar
- Built-in presets (not saved, always available):
  - "My Work" — `assignee_id_eq: current_user.id`
  - "All Bugs" — `task_type_eq: "bug"`
  - "Agent Tasks" — tasks with recent agent comments

**Technical notes:**
- Personal presets visible only to creator unless `shared: true`
- Built-in presets are frontend-only — constructed from known filter params
- `filters` jsonb stores the Ransack query hash

---

## Dependency Graph

```
Story 24.1 (Activity event model)
    │
    └──→ Story 24.2 (Activity feed API & UI)

Story 24.3 (Filtered views) — independent
    │
    └──→ Story 24.4 (Saved presets)
```

---

## Implementation Notes

- This is post-MVP — implement after Epic 20-23 are stable and in use for 2+ weeks
- Activity feed is the foundation for future analytics (time per column, bottleneck detection)
- Filtered views use URL params — views are shareable by copying URL
- Activity creation should be non-blocking — use `after_commit` callbacks or async job if needed
