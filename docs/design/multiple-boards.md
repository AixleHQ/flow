# Multiple boards per project — technical design

Status: **Proposal; not scheduled.** Written to size the work and settle the shape before
anyone commits to building it.
Date: 2026-09-30
Origin: customer feedback — "why only one board per project? Designers want their own board,
developers theirs, and tasks should move from one to the other."

## 1. Goal and product shape

A project can have several boards. Each board has its own columns, its own column workflow
bindings and its own view presets. A task lives on exactly one board at a time and can move to
a column on any other board of the same project.

The case we are designing for is a **handoff between teams that run different pipelines**:

```
Design board:  Brief → Research → Wireframes → Review → Done ─┐
                                                              │ move to board
Dev board:     Ready ◀────────────────────────────────────────┘ → In progress → Review → Done
```

Because column bindings already fire on "a task moved into this column", a handoff can start the
receiving team's workflow with no new trigger kind. The design workflow's last step moves the
task to *Dev → Ready*, and the binding on *Ready* starts the dev workflow. That is the part other
trackers do not have, and it is the main argument for building this at all.

Out of scope: per-board permissions or visibility (authorization stays project-level, §9);
moving tasks between projects; drag-and-drop between boards; a project-wide "all tasks" view
(§12 lists these as later).

## 2. Decisions

| Area | Decision |
|---|---|
| Cardinality | A project has **zero or more** boards. Zero stays legal: a project created over MCP or the API starts without one, as today. |
| Primary board | Exactly one board of a project that has any is **primary** (`boards.primary`, partial unique index). It is what old routes, task-less agent runs, MCP calls without a `board_id`, and template export resolve to. |
| Board names | Unique per project, case-insensitive. Agents and templates address boards by name, so a name must identify one board. |
| Task identity | Unchanged. Task and column ids are global. Every lookup by task or column id searches **all boards of the project**, so member routes and id-based tools need no board argument. |
| Moving between boards | The target **column** decides the target board. `TaskService.move` becomes the single path for both kinds of move and changes `board_id` when the column is on another board. |
| Triggers on handoff | Unchanged semantics: moving into a column with an `auto` binding fires it, whichever board the task came from. |
| Epics | A child must share the epic's **project**, not its board. Moving an epic moves only the epic. |
| API compatibility | Additive only. Board-scoped collection endpoints take an optional `board_id` and default to the primary board, so existing clients, an old JS bundle during a rolling deploy, and MCP clients keep working unchanged. |
| `project.board` | Removed, not aliased. Each of the ~40 callers chooses explicitly: `primary_board`, the task's board, or a project-wide lookup. An alias would quietly keep the wrong answer wherever the caller really meant "the task's board". |
| Deleting a board | Only a non-primary board with no active tasks, or the primary board when it is the project's last. |
| Templates | Phase 1 and 2 keep the single `board` section: export takes the primary board, install creates or merges into the primary board. `boards[]` is phase 3. |

## 3. What already exists

The data model is already board-scoped. The single-board rule is enforced in exactly three places:

- `app/models/project.rb:31`: `has_one :board`;
- `app/models/board.rb:11`: `validates :project_id, uniqueness: true`;
- `db/schema.rb`: `index_boards_on_project_id` (unique).

Everything below it already carries a `board_id` or hangs off a column:

- `board_tasks`, `board_columns`, `board_activities` and `board_view_presets` all have `board_id`.
- `column_workflow_bindings` key on `board_column_id`. Trigger events store `column_id`, and
  `TriggerEngine#create_subject_task` creates the subject task on `column.board`, so it is
  already correct with several boards.
- `column_transitions` store `from_column_id` / `to_column_id` with no board. A transition across
  boards needs no schema change.
- Realtime is per board record: `Board#broadcast_updates`, `BoardRefresh.request(board)`, and
  `inertia_cable_stream(board)` in `Web::Company::Projects::BoardsController`.
- Gates join `board_task → board → project` (`Gate.for_projects`), and
  `WorkflowService` only reads `run.board_task.board`. Both already work with several boards.
- `Project`'s `cached_board_tasks_count` subquery and `BoardTask.for_company` join boards by
  `project_id`, so they already sum across boards.
- Authorization is project-level. Every board policy ignores the record it is handed (§9).

Where "one board" is assumed, by layer:

| Layer | Where | Count |
|---|---|---|
| Public API v1 | `Api::V1::Projects::Board::ApplicationController#current_board` (`current_project.board`); `BoardController` create/update/destroy on the singular `resource :board` | 1 resolver, 6 controllers behind it |
| Web | `Web::Company::Projects::BoardsController#show`, `#find_task` (searches one board); singular `resource :board, only: :show`; the column lists sent by `WorkflowsController`, `TriggersController` (the project Triggers page) and `TrackersController` (the intake column picker) | 4 controllers |
| Personal MCP tools | `app/services/personal_tools/*`: `authorize!(project.board, …)` then `project.board&.board_tasks` / `board_columns` | 19 tools + `personal_mcp_guides.rb` |
| Agent tools | `app/services/internal_tools/board_*.rb` through `BoardContextResolver` | 14 tools |
| Agent prompt | `ContextBuilders::BoardContext` ("the project board", lists one board's columns) | 1 |
| Services | `WorkflowTriggers::Creator` (`BoardMissingError`), `TaskFilterable` (6 analytics services), `CompanyOverviewService`, `BuilderProjectSnapshot`, `ProjectResource` fallback count, `TaskService#extract_move_target` | 6 |
| Templates | `Templates::Exporter`, `Planner`, `Installer`, `Validator`, `Presenter`; `config/templates/template.v1.json` (`board` is one object) | 5 + schema |
| Frontend | `pages/Projects/Board/*`, `TaskDetailSidebar`, `SelectionBar`, workflow `TriggerFormPanel` column pickers, Aixle Builder "Board" tab, project overview, sidebar "Tasks" link | ~12 files |
| Docs | `docs/user-guide/board.md` and its bundled copy `app/frontend/pages/Docs/data/pages/board.md` say "Each project has exactly one Board"; also `docs/user-guide/index.md`, `docs/user-guide/mcp.md`, `docs/reference/api.md`, and the portal pages `using-flow.md`, `tasks.md`, `api-guide.md` | ~9 files |
| Seeds and tests | `db/seeds.rb` (`find_or_create_by!(project:)`); `installer_test` (merge), `creator_test` (`BoardMissingError`), `board_authorization_test` (singular route) | a handful |

Two existing gaps the design runs into, worth fixing whether or not it ships:

- **`board_create_task` bypasses `TaskService`.** The agent tool calls `board.board_tasks.create!`
  directly (`internal_tools/board_create_task.rb`), so an agent-created task records no
  `task_created` activity and never fires the auto-binding of the column it lands in. With
  boards, "an agent files a task on the Dev board" is a handoff, and it would silently not start
  the dev workflow.
- **Column names are not unique within a board.** The only unique index is
  `[board_id, position]`. `board_move_task`, `board_create_task` and `board_list_tasks` resolve
  `column_name` with `find_by(name:)`, which already picks an arbitrary column when two share a
  name. §7 does not make this worse, because a name is only ever resolved inside one board, but
  it is the same kind of ambiguity the board-name uniqueness rule avoids.

## 4. Data model

```
projects 1 ──── * boards (position, primary)
boards   1 ──── * board_columns 1 ──── 0..1 column_workflow_bindings
boards   1 ──── * board_tasks  (board_id always = board_column.board_id)
boards   1 ──── * board_activities, board_view_presets
```

### 4.1 Migration

```ruby
add_column :boards, :primary, :boolean, null: false, default: false
add_column :boards, :position, :integer

# Every existing board is its project's only board.
execute "UPDATE boards SET \"primary\" = TRUE, position = 1"
change_column_null :boards, :position, false

remove_index :boards, :project_id                      # the unique one
add_index :boards, :project_id
add_index :boards, :project_id, unique: true, where: "\"primary\"",
          name: "index_boards_one_primary_per_project"
add_index :boards, [ :project_id, :position ], unique: true
add_index :boards, "project_id, lower(name)", unique: true,
          name: "index_boards_on_project_id_and_lower_name"
```

`boards` holds one row per project today, so the table is small and these run inside the deploy
without `algorithm: :concurrently`. Existing board names cannot collide, because each project
has one board. `primary` is a reserved word in SQL and needs quoting in raw fragments; if that
turns out to be a nuisance, `is_primary` is the fallback name.

### 4.2 Associations and invariants

```ruby
class Project
  has_many :boards, -> { order(:position) }, dependent: :destroy
  has_one  :primary_board, -> { where(primary: true) }, class_name: "Board"
  has_many :board_tasks,   through: :boards
  has_many :board_columns, through: :boards
end
```

- **At most one primary** is the partial unique index. **At least one primary when any board
  exists** is model logic: the first board a project gets is created primary, and the primary
  board cannot be destroyed while other boards exist.
- **Changing the primary board** (`Board#make_primary!`) clears the old flag and sets the new one
  in one transaction, in that order. The partial index cannot be deferred, so the order matters.
- **Position** is assigned as `max + 1`, the same way `BoardColumn#assign_next_position` does it.
  Reordering reuses `Positions.reorder!`.
- `BoardTask#parent_same_board` becomes `parent_same_project`. `column_belongs_to_board` stays:
  a task's `board_id` must equal its column's `board_id`, and `TaskService.move` keeps them
  equal.

## 5. Moving a task to another board

`TaskService.move(task:, to_column:, position:, actor:, actor_type:)` keeps its signature. What
changes when `to_column.board_id != task.board_id`:

1. **Scope check.** `to_column.board.project_id` must equal `task.board.project_id`. Callers
   already find the column through `project.board_columns`, and the service checks again.
2. **Locks.** Same as today: both columns in id order, then the task.
3. **Write.** `task.update!(board: to_column.board, board_column: to_column, position: new_pos)`.
   The position is appended at the end of the target column unless one is given, as today.
4. **Trigger.** `record_pending_auto_trigger` runs against the target column, inside the
   transaction, exactly as for a move within one board. Cooldown and the pending-gate rule apply
   unchanged.
5. **History.**
   - One `ColumnTransition` from the old column to the new one. No schema change is needed.
   - A `task_moved` activity on the **target** board, with metadata
     `{ from_board:, to_board:, from_column:, to_column: }`.
   - A new `task_moved_out` activity on the **source** board, so its feed does not lose track
     of the task. The task timeline (`BoardActivity.for_task`) hides `task_moved_out`, because the
     `task_moved` row already tells the story.
   - Earlier activities keep their old `board_id`. That is correct: they happened on that board.
     Opening one of them goes through a `?task=` link, which §8.2 redirects to the task's
     current board.
6. **Realtime.** `BoardTask#touch_board` only reaches the task's board after the commit, which by
   then is the new board. The service also calls `BoardRefresh.request(old_board)`, so viewers of
   the source board see the card leave.

Behaviour kept on purpose:

- **Active runs do not block a move.** A move within one board does not block today, and
  handoff depends on it: the design workflow's last step moves its own task to the Dev board
  while its run is still active. Once the move commits, the running agent's
  `BoardContextResolver` follows the task to its new board (§7.1). Its prompt still lists the old
  board's columns, which is acceptable because the run is normally at its end. The bulk action
  keeps skipping tasks with active runs, as it does today.
- **A second run can start.** An auto-binding does not check whether the task has an active run.
  So a handoff into an auto column starts the receiving workflow while the sender's run is
  finishing. That is the intended chaining, and it is already how a move within one board
  behaves.
- **Epics.** Moving an epic moves the epic alone, and its children stay where they are. The
  children-count badge counts `child_tasks`, so it spans boards without change. The parent-epic
  picker offers the project's epics, not only the board's.

`TaskService#update` with a `board_column_id` (`extract_move_target`) looks the column up in
`task.board.project.board_columns` instead of `task.board.board_columns`, so a PATCH that names a
column on another board also goes through `move`.

`bulk_action(:move_to_column)` needs no change beyond the column lookup, because it calls `move`
once per task.

## 6. API and web routes

### 6.1 Public API v1

Additions:

```
GET    /api/v1/projects/:project_id/boards
POST   /api/v1/projects/:project_id/boards              { board: { name, preset? } }
GET    /api/v1/projects/:project_id/boards/:id
PATCH  /api/v1/projects/:project_id/boards/:id          { board: { name } }
POST   /api/v1/projects/:project_id/boards/:id/make_primary
PATCH  /api/v1/projects/:project_id/boards/reorder      { board_ids: [...] }
DELETE /api/v1/projects/:project_id/boards/:id
```

Existing routes are unchanged and keep their meaning:

- The singular `resource :board` (create, update, destroy) acts on the **primary** board.
  `create` still returns 422 once the project has a board; additional boards are created through
  `POST /boards`, so no existing client sees a behaviour change.
- **Collection endpoints** accept an optional `board_id` and default to the primary board:
  `GET/POST /tasks`, `GET/POST /columns`, `PATCH /columns/reorder`, `GET /activities`,
  `GET/POST /view_presets`, `POST /tasks/bulk_actions`.
- Where the request names a column, the board comes from it: `GET /tasks?board_column_id=`,
  `POST /tasks` with `board_column_id`, `reorder` with `column_ids`. The columns in one `reorder`
  call must all belong to one board.
- **Member endpoints** (`/tasks/:id/…`, `/columns/:id/…`, and the nested comments, assets,
  gates, transitions, activities and statistics) find the record through
  `current_project.board_tasks` / `board_columns`, and `current_board` becomes the record's
  board. `PATCH /tasks/:id/move` accepts a `column_id` on any board of the project.

`Board::ApplicationController#current_board` is where this happens:

```ruby
def current_board
  @current_board ||=
    if params[:board_id].present? then current_project.boards.find(params[:board_id])
    else current_project.primary_board || raise(ActiveRecord::RecordNotFound)
    end
end
```

Member controllers override it with the found record's board. Board-level `@summary` comments
(OasRails) and `docs/reference/api.md` document `board_id`.

Nothing here removes or renames a path, so there is no contract phase.

### 6.2 Web

```
GET /company/projects/:project_id/boards/:id           BoardPage for that board
GET /company/projects/:project_id/board                302 → primary board, or → the task's board with ?task=
GET /company/projects/:project_id/board?task=123        302 → /boards/<board of 123>?task=123
```

The singular route stays forever, because it is in links people have pasted, in the sidebar, in
agent comments and in the docs. `BoardsController#find_task` searches the project's boards, and
when the task lives on another board, `show` redirects instead of rendering nil.

`companyProjectBoardPath` keeps generating the redirecting path, and a new
`companyProjectBoardsPath(projectId, boardId)` is added. Regenerate `routes.ts` under
`RAILS_ENV=test`: a development run bakes the letter_opener helpers into the shipped file.

## 7. Agents and MCP

### 7.1 Agent tools (`InternalTools::Board*`)

These tools are only injected into `workflow_step` sessions. Their board comes from
`BoardContextResolver`: the run's task's board, or else `session.project.board`. The second
branch is used by manual runs and by triggers with `subject_policy: none`.

| Change | Tools |
|---|---|
| Resolver fallback becomes `session.project.primary_board`. The task branch is unchanged. | `BoardContextResolver` |
| Task and comment lookups by id search `project.board_tasks`, so a task-less run can reach tasks on any board. This is the scope it has today, because today the one board is the whole project. | `add_comment`, `attach_asset`, `create_gate`, `get_comments`, `get_task`, `get_task_assets`, `list_gates`, `manage_tags`, `update_task` |
| New optional `board` param (a name, case-insensitive, or an id). `column_name` is resolved inside that board. Default: the task's current board. | `move_task` |
| New optional `board` param. Default: the resolved board. **Goes through `TaskService.create`**, which closes the gap described in §3. | `create_task` |
| New optional `board` param; every row in the result carries `board`. | `list_tasks` |
| Returns the resolved board with its columns, plus `boards: [{ id, name, primary, columns: [names] }]` for the whole project, so an agent can find a handoff target. | `get_board_info` |
| No change. | `list_members` |

`ContextBuilders::BoardContext` names the task's board instead of saying "the project board".
When the project has other boards, it adds one line listing them ("Other boards in this project:
Dev, QA — use board_move_task with `board` to hand a task over"). It does not list their columns:
`board_get_board_info` is one call away, and the prompt stays short.

A bad `board` value returns the list of valid board names in the error, the same way a bad
`column_name` should.

### 7.2 Personal MCP tools

| Change | Tools |
|---|---|
| New tools: `list_boards`, `update_board` (rename, `primary: true`), `delete_board` (asks the user first, like every `delete_*`), `reorder_boards`. | new |
| `setup_board` stops refusing when a board exists and creates another one. `name` becomes required once the project has a board, and a `primary` flag is optional. The name stays `setup_board`, because it is in the server instructions and in prompts people have saved. | `setup_board` |
| Optional `board_id`, defaulting to the primary board. | `list_board_columns`, `create_board_column`, `list_board_tasks` (unless `column_id` is given) |
| The board comes from the column argument, so no new param is needed. | `create_board_task`, `reorder_board_columns`, `move_board_task` (any column of the project, which makes it a cross-board move) |
| Lookup by id searches the project's boards. | `get_board_task`, `update_board_task`, `archive_board_task`, `delete_board_task`, `update_board_column`, `delete_board_column`, `add_board_comment`, `list_board_comments`, `list_gates`, `delete_gate`, `read_asset`, `trigger_task_workflow` |
| `authorize!(project.board, …)` becomes `authorize!(board_or_nil, …)`. The policies are project-level (§9), so this does not change who may do what. | all |

`Tools::PersonalMCPGuides` stops saying "A project owns a board" and explains primary and
additional boards. `create_workflow_trigger` / `update_workflow_trigger` accept any column of the
project (§7.3).

### 7.3 Triggers and the workflow editor

- `WorkflowTriggers::Creator` finds `board_column_id` and `subject_column_id` in
  `@project.board_columns`. `BoardMissingError` stays for a project with no boards.
- `Web::Company::Projects::WorkflowsController`, `TriggersController` and `TrackersController`
  send columns from all boards, each with `board_id` and `board_name`. `TriggerFormPanel`'s
  column pickers and the tracker intake column picker become grouped selects
  ("Design / Review", "Dev / Ready").
- The task-tracker design (`task-tracker-integrations.md` §6.8) creates intake tasks through a
  subject column. That works unchanged, because the column already names its board.

### 7.4 Aixle Builder

`BuilderProjectSnapshot` lists every board, with its name, whether it is primary, and its columns
and bindings. `AixleBuilderController`'s deferred `board_columns` prop becomes `boards`, and the
Builder's "Board" tab shows one section per board.

## 8. Frontend

### 8.1 Board page

- **Switcher** in the page header. With one board it shows only the board name and a "New board"
  item in its menu, so a single-board project looks exactly as it does today. With several it
  lists them in position order and marks the primary one.
- **New board** reuses `BoardPresetPicker` (presets or empty), and asks for a name.
- **Board settings** (`BoardSettingsDialog`) gains rename, "Make primary" and "Delete board"
  (§10) at the top. Everything about columns stays as it is.
- Every API call from the page passes `board_id`: `useBoardTaskPages`,
  `useBoardActivitiesLoadMore`, `ViewPresetMenu`, column CRUD and reorder, and task create. Calls
  addressed by task or column id need nothing.
- The props gain `boards: [{ id, name, primary }]`. `epics` becomes project-wide. `board_tags`
  stays per board.
- The `board:${id}:collapsedColumns` localStorage key is already per board.
- Optionally, the last board a viewer opened is remembered in localStorage, and the sidebar
  "Tasks" link goes straight to it. Without that the link hits `/board` and lands on the primary
  board.

### 8.2 Moving between boards

- **Task drawer** (`TaskDetailSidebar`): a "Board" select above the existing "Column" select.
  Picking a board fills the column select with that board's columns, preselecting the first one,
  and confirming calls `PATCH /tasks/:id/move`. Because the card leaves the current board, the
  drawer closes and a toast offers "Open on Dev".
- **Bulk actions** (`SelectionBar`): "Move to column" lists every board's columns, grouped by
  board.
- **Drag-and-drop** stays within one board. Dragging between boards would mean showing two boards
  at once, and that is not worth it for v1.
- **Deep links** `?task=` work from any board URL and redirect to the task's board (§6.2).

### 8.3 Elsewhere

- **Project overview:**
  - `BoardTaskDistributionService` groups by board, then column. Today it would interleave the
    columns of different boards by position.
  - `CompanyOverviewService#board_tasks_scope` uses `project.board_tasks`.
  - "Open board" goes to the `/board` redirect.
- `TaskFilterable` uses `project.board_tasks` and optionally takes a board filter. The analytics
  that include it become project-wide, which is what their labels already say.
- `ProjectResource`'s fallback count uses `project.board_tasks`.
- **Generated types** (`typelize`): `Board` gains `primary` and `position`; `BoardColumn` and
  `BoardTask` gain `boardId`.

## 9. Permissions

Unchanged, and deliberately so. Every board policy checks the project (`project_accessible?`,
`project_writable?`, `project_admin?`) and ignores the board record. Board create, rename,
delete, reorder and "make primary" follow the existing board create/update/destroy rules: admin
on the web policy, writable on the API policy subclasses, as today.

"Designers cannot see the dev board" is **per-board visibility**. That is a different feature:
it needs board membership, filtered board lists, filtered task lookups in every tool above,
filtered analytics, and a rule for what happens when a task moves to a board the actor cannot
see. It is left out on purpose. If the feedback turns out to be about visibility rather than
separate pipelines, this design does not answer it (§11, option B).

## 10. Deleting a board

- The **primary board** can be deleted only when it is the project's last board. That returns the
  project to the no-board state, as `DELETE /board` does today. With other boards, another board
  must be made primary first.
- A **non-primary board** can be deleted only when it has no **active** tasks. The dialog offers
  "Move all tasks to…" (a bulk move) first. After confirmation, archived tasks and history go with
  the board, as with today's single-board delete (`dependent: :destroy`).
- The confirmation lists the workflow bindings on its columns. Deleting the columns deletes the
  bindings, so those workflows stop being started from the board.

## 11. Alternatives considered

**A. Column groups on one board.** Add a `group` to columns ("Design", "Dev"). Each group
collapses and can be filtered through view presets. Moving between teams is then an ordinary move
within the board, so agents, MCP, API, templates and triggers need no change at all, and it would
take about 3–4 days. The costs are that everyone shares one wide board, a team's "own board" is a
saved filter rather than a place, and the board settings, epic and tag lists stay shared. This is
the right answer if the request turns out to be mostly about **different columns** for different
people, and a weak one if teams think of their board as theirs.

**B. One project per team.** This needs nothing new for the boards themselves. But agents,
workflows, skills, tools, MCP servers, repositories and config items all belong to one project,
so each team duplicates them. Moving a task between projects would also break its runs, gates,
assets and assignee rules. Rejected.

**C. View presets only.** Presets already exist and filter by tag, assignee and so on. They do
not give a team its own columns, so they miss the point of the request. Rejected as an answer to
it, although they remain the answer to "I only want to see my tasks".

## 12. Phasing

Rough sizes are for one engineer. Each phase ships on its own.

1. **Backend foundation, no visible change** (~5–6 days):
   - the migration and the associations;
   - the sweep of the ~40 `project.board` callers, each making an explicit choice;
   - the `board_id` params and the `/boards` routes;
   - the cross-board `TaskService.move`, with `task_moved_out` and the double refresh;
   - the agent tool changes, including `board_create_task` going through `TaskService`, and the
     MCP tools and guides;
   - trigger column lookup, `TaskFilterable`, the overview services and `BuilderProjectSnapshot`.

   Until someone creates a second board through the API or MCP, the product behaves exactly as
   today, because the primary board is the only board. This phase also has to reach production
   before phase 2: a rolling deploy can serve new JS from an old pod, and the new pages call
   routes that only the new backend has.
2. **UI** (~4–5 days):
   - the switcher, new board, rename, make primary and delete;
   - the drawer "Board" select, the grouped bulk move, and the grouped column pickers in the
     workflow editor;
   - the overview grouping, the Builder tab and the deep-link redirects;
   - the user docs listed in §3. `/docs` serves the bundled copies under
     `app/frontend/pages/Docs/data/pages/`, so each `docs/user-guide/` edit is made in both.
3. **Templates** (~3 days, plus a `flow-templates` validator release):
   - The package gets `boards: [{ key, name, primary?, columns: [...] }]`, next to the old
     `board`. `board` stays valid and means one primary board, and a package has one or the other.
   - Column keys become unique across the whole package, so `triggers[].column` and
     `subject_column` keep referring to a bare key.
   - Export writes every board. Install can create each board as a new board or merge it into a
     same-named one.
   - The `flow-templates` CI runs the validator from the agent image, so the schema change needs
     a `main-images` release before templates there can use `boards`.

Later, only when asked for:

- a project-wide task list or search across boards;
- drag-and-drop between boards;
- per-board visibility (§9).

Tests follow `docs/testing.md`:
- **Model tests:** the primary invariants and `parent_same_project`.
- **Service tests:** `TaskService.move` across boards, covering the auto-trigger on the target
  column, both activity rows, both refreshes, and the rejection of another project's column.
- **Request tests:** the API defaults to the primary board without `board_id`, and member
  routes work for tasks on non-primary boards.
- **Tool tests:** one per agent and MCP tool family, using the project-wide lookup.
- **Frontend (Vitest):** the drawer's board-then-column flow and the switcher.

The three existing tests that assume one board change with phase 1.

## 13. Decisions

### 13.1 Proposed

| # | Question | Proposal |
|---|---|---|
| 1 | Explicit primary board, or "the first by position"? | **Explicit.** Reordering boards in the UI must not change which board a task-less agent run writes to. |
| 2 | Keep `project.board` as an alias for the primary board? | **No.** Every caller is decided explicitly in phase 1 (§2). |
| 3 | Nested `/boards/:board_id/tasks` routes, or a `board_id` param on the existing ones? | **Param.** Task and column ids are global, so member routes need no board. Keeping the existing paths is what makes the change additive. |
| 4 | Epics across boards? | **Allowed within a project.** "Epic on the product board, stories on design and dev" is the first thing a team with several boards does. |
| 5 | Block a cross-board move while the task has an active run? | **No.** Handoff is exactly that: the run moves its own task (§5). |
| 6 | Unique board names per project? | **Yes, case-insensitive.** Agents and templates address boards by name. |

### 13.2 Open (product)

1. **Build it at all, or wait for the request to repeat?** If it is built, this design or
   alternative A?
2. Is the request about **separate pipelines** (this design) or **visibility** (§9, not
   covered)? That is the question to put back to the customer.
3. **Sidebar:** keep one "Tasks" entry with the switcher on the page, or list the boards in the
   sidebar?
4. **Deleting a board that still has archived tasks:** delete them with it (proposed), or move
   them to the primary board?
