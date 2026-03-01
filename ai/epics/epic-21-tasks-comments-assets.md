# Epic 21: Tasks, Comments & Assets

> Task CRUD with types and epic→story hierarchy, flat comments with tags and author_type, task-level file attachments.

**Phase:** 13 (Depends on: Epic 20 Board & Column Foundation)

**PRD:** [Board & Tasks PRD](../prd/board-tasks.md)

**User Outcome:** Users can create and manage tasks on the board with types (epic/story/bug), organize them in epic→story hierarchies, communicate via tagged comments, and attach files to tasks.

**FRs Covered:** FR12, FR13, FR14, FR15, FR16, FR17, FR18, FR19, FR20, FR21, FR22, FR23, FR24, FR25, FR26, FR27

---

## Stories

### Story 21.1: Task Model & CRUD

**As a** user,
**I want** to create tasks with structured fields,
**So that** I can track work items on my board.

**Acceptance Criteria:**
- Migration creates `board_tasks` table:
  - `id`, `board_id` (references, not null), `board_column_id` (references, not null)
  - `title` (string, not null), `description` (text, nullable)
  - `task_type` (string, not null, default: "not_specified")
  - `priority` (string, nullable)
  - `assignee_id` (references users, nullable)
  - `position` (integer, not null) — position within column
  - `parent_task_id` (references board_tasks, nullable) — for epic→story
  - `tags` (string array or jsonb, default: [])
  - `timestamps`
- `BoardTask` model with:
  - `belongs_to :board`, `belongs_to :board_column`
  - `belongs_to :assignee, class_name: "User", optional: true`
  - `enumerize :task_type, in: %i[epic story bug not_specified], default: :not_specified`
  - `enumerize :priority, in: %i[low medium high critical], default: nil`
- Task CRUD API at `api/v1/company/projects/:project_id/board/tasks`
- Pundit policy: Admin and Collaborator can CRUD tasks
- Serializer: `BoardTaskSerializer` with all fields + `children_count`, `comments_count`, `assets_count`

**Technical notes:**
- `board_column_id` enforces one task in exactly one column (FR18)
- Position is within column, not global — allows card ordering within columns
- Tags stored as PostgreSQL array column: `t.string :tags, array: true, default: []`

---

### Story 21.2: Epic → Story Hierarchy

**As a** user,
**I want** to create parent-child relationships between tasks,
**So that** I can organize epics with their stories.

**Acceptance Criteria:**
- `BoardTask` gains `belongs_to :parent_task, class_name: "BoardTask", optional: true`
- `BoardTask` gains `has_many :child_tasks, class_name: "BoardTask", foreign_key: :parent_task_id`
- Validation: parent must be `task_type: :epic`, child can be any type
- Validation: parent and child must belong to same board
- Validation: max one level of nesting (no epic→story→sub-story)
- API: create task with `parent_task_id` parameter
- API: `GET /tasks?parent_task_id=X` to list children of an epic
- Serializer includes `parent_task_id` and `children_count`

**Technical notes:**
- No cascading delete — deleting epic does not delete stories (sets `parent_task_id` to nil)
- Epic can have stories in different columns

---

### Story 21.3: Task Assignment

**As a** user,
**I want** to assign tasks to project collaborators,
**So that** team members know what they're responsible for.

**Acceptance Criteria:**
- `assignee_id` references `users` table
- Validation: assignee must be a member of the project (collaborator or admin)
- API: update task with `assignee_id` parameter
- API: filter tasks by assignee: `GET /tasks?assignee_id=X`
- Unassign by setting `assignee_id` to null

**Technical notes:**
- Assignee is used for agent authorization — agent acts as task assignee when performing MCP operations

---

### Story 21.4: Move Task Between Columns

**As a** user,
**I want** to move tasks between columns,
**So that** I can track task progress through my workflow stages.

**Acceptance Criteria:**
- API endpoint: `PATCH /tasks/:id/move` with `column_id` and optional `position`
- No transition constraints — any task can move to any column (FR15)
- Task position updated in target column
- Source column positions re-compacted after move
- Database-level: update `board_column_id` with row-level lock to prevent race conditions
- Returns updated task

**Technical notes:**
- This endpoint is critical — it's the trigger point for workflow bindings (Epic 23)
- Row-level lock: `task.lock!` before column change to prevent concurrent moves
- Position in target column: default to end if not specified

---

### Story 21.5: Task Comment Model

**As a** user,
**I want** to add comments to tasks with tags and author attribution,
**So that** I can communicate with team members and AI agents through structured feedback.

**Acceptance Criteria:**
- Migration creates `task_comments` table:
  - `id`, `board_task_id` (references, not null)
  - `body` (text, not null)
  - `author_id` (references users, not null)
  - `author_type` (string, not null, default: "human")
  - `tags` (string array, default: [])
  - `created_at` (timestamp, not null)
- `TaskComment` model with:
  - `belongs_to :board_task`, `belongs_to :author, class_name: "User"`
  - `enumerize :author_type, in: %i[human agent system], default: :human`
  - No `updated_at` — comments are append-only (FR22)
- Comments API: `POST /tasks/:task_id/comments` (create only, no update/delete)
- `GET /tasks/:task_id/comments` with filters: `tag`, `author_type`
- Serializer: `TaskCommentSerializer` with all fields + `author_name`

**Technical notes:**
- No update or delete endpoints — comments are immutable (FR22)
- Tags are free-form strings: `tech_design`, `code_review`, `qa_report`, `feedback`, or custom
- Filter by tag: `where("? = ANY(tags)", tag_param)`
- `author_type` is set by the system: `human` for web UI, `agent` for MCP tool, `system` for auto-generated

---

### Story 21.6: Task Assets

**As a** user,
**I want** to attach files to tasks,
**So that** I can share documents, designs, and agent outputs on specific tasks.

**Acceptance Criteria:**
- Migration creates `task_assets` table:
  - `id`, `board_task_id` (references, not null)
  - `name` (string, not null)
  - `author_id` (references users, not null)
  - `author_type` (string, not null, default: "human")
  - `tags` (string array, default: [])
  - Shrine column: `file_data` (text)
  - `timestamps`
- `TaskAsset` model with Shrine uploader (`TaskAssetUploader`)
- Upload endpoint: `POST /tasks/:task_id/assets` (multipart)
- Download: presigned URL via serializer
- List: `GET /tasks/:task_id/assets` with optional `tag` filter
- Delete endpoint for admin/owner
- Serializer: `TaskAssetSerializer` with `id`, `name`, `file_url`, `file_size`, `tags`, `author_type`, `created_at`

**Technical notes:**
- Reuses existing Shrine + S3 infrastructure
- Storage path: `task_assets/{board_task_id}/{filename}`
- `author_type` same as comments: `human` / `agent` / `system`

---

## Dependency Graph

```
Story 21.1 (Task model + CRUD)
    │
    ├──→ Story 21.2 (Epic → Story hierarchy)
    │
    ├──→ Story 21.3 (Task assignment)
    │
    ├──→ Story 21.4 (Move task between columns)
    │
    ├──→ Story 21.5 (Comments with tags)
    │
    └──→ Story 21.6 (Task assets)
```

All stories depend on 21.1. Stories 21.2-21.6 are independent of each other.

---

## Implementation Notes

- All API endpoints scoped through project: `current_company.projects.find(params[:project_id]).board.tasks`
- Comment immutability is enforced by API surface (no PATCH/DELETE endpoints), not by DB constraint
- Tags use PostgreSQL array type — enables `ANY()` queries for efficient filtering
- Task assets follow same Shrine pattern as existing `Asset` model but scoped to tasks
