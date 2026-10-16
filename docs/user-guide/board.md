# Board

Each project has exactly one Board. A Board is a column-ordered Kanban
where every card represents a unit of work — and where automation lives.

## Anatomy

| Concept             | What it is                                                       |
| ------------------- | ---------------------------------------------------------------- |
| **Column**          | A named, ordered stage (e.g. *In Progress*, *Code Review*).       |
| **Task**            | A card with title, description (markdown), type, priority, tags. |
| **Subtask**         | One level of nesting (epic → story).                              |
| **Comment**         | Threaded discussion; agents can tag comments (`code_review`, `qa_report`). |
| **Asset**           | File attached to a task; the agent fetches it with `board_get_task_assets` (not mounted in the container). |
| **Wait**            | External blocker — e.g. waiting for a GitHub PR check.            |
| **Activity log**    | Immutable event stream — every move, comment, run.                |

## Column → Workflow Bindings

This is the trigger that makes the board *do* things. Each column can
have **at most one** `ColumnWorkflowBinding`:

| Field             | Purpose                                                                |
| ----------------- | ---------------------------------------------------------------------- |
| `workflow_id`     | Which workflow to run when a card enters the column.                   |
| `trigger_mode`    | `manual` (a button in the UI) or `auto` (fires on card entry).         |
| `cooldown_seconds`| Minimum gap between two auto-triggers of the same card (default `5`).  |

When a card enters a bound column in auto mode and:

- there is **no pending TaskWait** on the card, **and**
- there is **no active WorkflowRun** on the card,

a new non-interactive `WorkflowRun` starts. The agent reads the card
title, description, comments, and attached assets as context.

## Presets

When creating a project, pick one of three column presets:

| Preset          | Columns                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| `simple_kanban` | Backlog → In Progress → Done                                                                            |
| `dev_team`      | Backlog → Tech Design → Implementation → Code Review → QA → Ready for Release → Done                   |
| `full_sdlc`     | A full 19-column SDLC layout from Design through Release                                                |

Each preset column has a `purpose` field — a short description that
gets injected into the agent's context so it knows what "Code Review"
means in your team.

Over the personal MCP server the same choice is the `setup_board` tool —
a project created there has no board until it runs.

## Tasks and agents — what context the agent sees

When a board-triggered workflow run starts, the agent receives:

- Task title, number, internal id, column, priority, tags and assignee.
- The complete description when it is at most 1,500 characters; otherwise a
  pointer to read it with `board_get_task`, without a truncated copy.
- Instructions to read the task's comments before changing code. Comments are
  fetched with `board_get_comments`; they are not copied into the initial context. Use
  `author_type: "human"` for human comments (`"user"` remains a compatible alias).
- For a subtask, its parent epic's title, number and internal id, with instructions
  to read the epic's full description and comments.
- A `board_list_tasks(parent_task_id: …)` pointer to discover subtasks of the
  current epic, or siblings of the current subtask. The response is paginated;
  follow `has_more` and `offset` when further tasks are relevant.
- Board column names, with the current column marked.

Read referenced or relevant related tasks and their comments before implementing.
Keep the task and epic requirements consistent with agreed decisions; report
unresolved conflicts instead of silently choosing one. A relationship does not
impose execution order or merge another task's branch: verify that prerequisite
PRs or commits are present on the working branch.

The task's attachments are available through `board_get_task_assets` (they are
not mounted in the container). Other tasks' descriptions, comments and run
transcripts are not automatically inherited. Arbitrary links in external trackers
are not traversed by this epic/subtask mechanism.

This is the **BoardContext** builder — one of the layers in the agent
context stack. See [agents.md](agents.md#how-context-is-built) for the
full stack.

## Task IDs

Every task has a numeric id that is stable for its lifetime. It appears next to
the task title on the card, in collapsed-column chips (hover to see), and in the
detail drawer header. Clicking `#42` copies the number to the clipboard.

### Finding a card by id

Press `/` to open search and type the id (`42` or `#42`). The exact match
surfaces first, above any title matches. Title search continues to work as
before — a query like `login` still finds cards by name.

## Common gotchas

- **A card "stuck" in a bound column** usually means there's a
  `TaskWait` on it (e.g. a CI check that never completed). Open the
  card and clear the wait — the binding will re-evaluate.
- **Auto-trigger didn't fire** — check the `cooldown_seconds` window
  and whether the binding was set to `manual` instead of `auto`.
- **Two workflows on one column** is not supported. Build a single
  workflow with branching steps instead.
