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
| **Asset**           | File attached to a task; passed to the agent at `/workspace/assets/`. |
| **Gate**            | External blocker — e.g. waiting for a GitHub PR check.            |
| **Activity log**    | Immutable event stream — every move, comment, run.                |

## Column → Workflow Bindings

This is the board-native trigger. Each column can have **at most one**
`ColumnWorkflowBinding`. It's one of several trigger sources — for schedules,
Slack and webhooks (and the full model), see
[Triggers and Gates](/docs/triggers-and-gates).

| Field             | Purpose                                                                |
| ----------------- | ---------------------------------------------------------------------- |
| `workflow_id`     | Which workflow to run when a card enters the column.                   |
| `trigger_mode`    | `manual` (a button in the UI) or `auto` (fires on card entry).         |
| `cooldown_seconds`| Minimum gap between auto-triggers (default `5`).                       |

When a card enters a bound column in auto mode and:

- there is **no pending Gate** on the card, **and**
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

## Tasks and agents — what context the agent sees

When a board-triggered workflow run starts, the agent receives:

- Task title, description, type, priority, tags.
- All task comments (most recent first), with their tags.
- All task assets, downloaded to `/workspace/assets/`.
- Task transitions (movement history).
- Column purpose (so the agent knows the stage it's working in).

This is the **BoardContext** builder — one of the layers in the agent
context stack. See the Agents page (How context is built) for the full
stack.

## Common gotchas

- **A card "stuck" in a bound column** usually means there's a
  `Gate` on it (e.g. a CI check that never completed). A gate is not a
  trigger — it holds the auto-trigger until it resolves. Open the card
  and clear the gate, and the binding re-evaluates.
- **Auto-trigger didn't fire** — check the `cooldown_seconds` window
  and whether the binding was set to `manual` instead of `auto`.
- **Two workflows on one column** is not supported. Build a single
  workflow with branching steps instead.
