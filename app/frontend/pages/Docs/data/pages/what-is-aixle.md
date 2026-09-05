Aixle Flow is a Kanban board where every column can trigger an AI agent workflow. Move a card, a workflow starts, an agent runs in a container, and the results come back to the board.

## Key concepts

A small set of primitives gives you the complete mental model.

## How it works

A **Company** owns shared resources. Inside it, **Projects** each have
one **Board**. A Board has ordered **Columns**; each column can be
**bound to a Workflow**. Drop a card into the column and the workflow
starts. A Workflow is a DAG of **Steps**; each Step is one **Agent**
session running in an isolated **container**, producing artifacts and
optionally pushing PRs. Steps can depend on each other (parallel
branches are fine), retry on failure, or block on a human approval.
Every run is tracked with cost, tokens, and a full log.

That's the whole product.

### The board

Each project has one Kanban board with ordered columns. You can create
columns manually or start from a preset: `simple_kanban`, `dev_team`,
or `full_sdlc`. Each column has a **purpose** — a short description
that the agent receives as context when it runs in that column.

> **info** **Column bindings are the trigger.** Bind a column to a workflow and set `trigger_mode: auto` — the workflow starts as soon as a card enters the column.

### Agents and workflows

A **Workflow** is a DAG of Steps. Each Step is one Agent session in one
container. Steps can run in parallel, depend on each other's outputs,
and retry on failure. The **Aixle Builder** (project sidebar → "Build
with AI") generates workflows from a plain-language description.

An **Agent** is a persona (who it is, how it communicates, what
principles it follows) running on top of an LLM CLI runtime —
`claude_code`, `cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, or `grok`. The same persona
can run on any runtime.

### Containers

Every step runs in a fresh Docker container. The agent finds:

- `/workspace/outputs/` — where it writes deliverables.
- `/workspace/assets/` — pre-loaded input files (task attachments,
  workflow assets).
- `/workspace/repo/` — clones of the repositories the step selected.

> **tip** **Open source and self-hosted.** Aixle Flow runs entirely in your own infrastructure via Docker Compose. No cloud dependency, no vendor lock-in.
