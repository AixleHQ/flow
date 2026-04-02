# Epic 20: Board & Column Foundation

> Data models, presets, column customization, and `purpose` field for the Board & Tasks module.

**Phase:** 13 (Depends on: Epic 3 Projects & Collaboration)

**PRD:** [Board & Tasks PRD](../prd/board-tasks.md)

**User Outcome:** Users can create a board per project from presets, customize columns freely, and describe each column's purpose for both humans and AI agents.

**FRs Covered:** FR1, FR2, FR3, FR4, FR5

---

## Problem

AIXLE has workflows and agent sessions but no task management. Users track tasks in external tools (Linear, Jira) — disconnected from the AI execution pipeline. Board & Tasks creates a native task board where column transitions trigger workflows.

This epic establishes the data foundation: Board, Column models with presets and the `purpose` field that makes the board self-documenting for agents.

---

## Stories

### Story 20.1: Board Model & Project Association

**As a** user,
**I want** to create a board for my project,
**So that** I have a dedicated task management space integrated with AIXLE workflows.

**Acceptance Criteria:**
- Migration creates `boards` table: `id`, `project_id` (references, not null, unique), `name` (string, not null), `preset_origin` (string, nullable), `timestamps`
- `Board` model with `belongs_to :project`, uniqueness validation on `project_id`
- `Project` model gains `has_one :board`
- Board CRUD API at `api/v1/company/projects/:project_id/board` (singular resource)
- Create endpoint accepts `preset` parameter (see Story 20.3)
- Pundit policy: Admin can create/delete board, Collaborator can read
- Serializer: `BoardSerializer` with `id`, `name`, `preset_origin`, `columns` (embedded)

**Technical notes:**
- Unique index on `project_id` enforces one board per project at DB level
- `preset_origin` stores which preset was used (nil if custom), detaches on first modification

---

### Story 20.2: Column Model with Purpose Field

**As a** user,
**I want** to manage columns on my board with names, positions, and purpose descriptions,
**So that** I can define my workflow stages and communicate their intent to agents.

**Acceptance Criteria:**
- Migration creates `board_columns` table: `id`, `board_id` (references, not null), `name` (string, not null), `position` (integer, not null), `purpose` (text, nullable), `timestamps`
- `BoardColumn` model with `belongs_to :board`, acts_as_list (or manual position management)
- Columns API nested under board: CRUD operations
- Column operations: add, remove, rename, reorder
- `purpose` field: free text describing what happens at this stage (e.g. "Technical design is being created. Expected output: comment with tag tech_design")
- Reorder endpoint: accepts array of column IDs in new order, updates positions in transaction
- Pundit policy: Admin can manage columns, Collaborator can read
- Serializer: `BoardColumnSerializer` with `id`, `name`, `position`, `purpose`, `workflow_binding` (see Epic 23)

**Technical notes:**
- Use `board_columns` table name to avoid conflict with Rails reserved word `columns`
- Position must be unique per board — `validates :position, uniqueness: { scope: :board_id }`
- Reorder uses bulk update in single transaction

---

### Story 20.3: Board Presets

**As a** user,
**I want** to create a board from a preset template,
**So that** I get a sensible starting point without configuring everything from scratch.

**Acceptance Criteria:**
- Three built-in presets defined in `BoardPresets` service/constant:
  - **Simple Kanban:** Backlog, In Progress, Done
  - **Dev Team:** Backlog, Tech Design, Implementation, Code Review, Done
  - **Full SDLC:** Backlog, Estimation, Tech Design, Implementation, Code Review, QA, Done
- Each preset defines: column names, positions, and default `purpose` texts
- Board creation with `preset` parameter creates board + columns in single transaction
- `preset_origin` field records which preset was used
- API returns available presets via `GET /board/presets`

**Technical notes:**
- Presets are Ruby constants/frozen hashes, not database records
- Purpose texts for presets provide sensible defaults agents can use immediately
- Example: Dev Team preset, Tech Design column purpose: "Technical design phase. Agent should analyze requirements, propose architecture, and produce a tech design document as a comment with tag 'tech_design'."

---

### Story 20.4: Preset Detachment on Modification

**As a** user,
**I want** my board to become independent after I modify columns,
**So that** I can freely customize without being constrained by the preset.

**Acceptance Criteria:**
- Any column modification (add, remove, rename, reorder) sets `board.preset_origin` to nil
- Modification detection: before_save callback on BoardColumn checks if board still matches preset
- Simpler approach: on any column write operation, nil out `preset_origin` if currently set
- UI can show "Custom" instead of preset name when detached

**Technical notes:**
- Detachment is one-way — once detached, cannot re-attach to preset
- This is a simple nil-out, not a complex diff check

---

## Dependency Graph

```
Story 20.1 (Board model)
    │
    └──→ Story 20.2 (Column model + purpose)
             │
             ├──→ Story 20.3 (Presets)
             │
             └──→ Story 20.4 (Preset detachment)
```

---

## Implementation Notes

- Board is always accessed through project scope: `current_company.projects.find(params[:project_id]).board`
- No standalone board routes — always nested under project
- `purpose` field is the key differentiator — make it prominent in API responses
- Column position management can use simple integer sorting, no need for acts_as_list gem if we handle reorder in a service
