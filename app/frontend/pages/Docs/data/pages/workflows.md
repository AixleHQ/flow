# Workflows

A Workflow is a DAG of Steps that together accomplish a business
process — a code review, a feature spec, a bug triage. Each Step is one
agent session in one container.

## Anatomy of a Workflow

| Field                            | Description                                                                 |
| -------------------------------- | --------------------------------------------------------------------------- |
| `name`                           | Unique within its scope (Company or Project).                                |
| `description`                    | What the workflow accomplishes.                                              |
| `config.base_tool_ids`           | Tools always available to every step in this workflow.                       |
| `config.base_skill_ids`          | Skills always injected into agent context.                                   |
| `config.base_mcp_server_ids`     | MCP servers always connected.                                                |
| `config.base_asset_ids`          | Files always pre-loaded into `/workspace/assets/`.                           |
| `config.inherit_all_project_resources` | If true, all project-level resources merge in additively.              |
| `execution_mode`                 | `interactive`, `non_interactive`, or `mixed` (per-step).                     |

## Anatomy of a Step

One Step = one agent session = one container = one major deliverable.

| Field                  | Description                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| `name`                 | Step name.                                                               |
| `position`             | Order in workflow.                                                       |
| `instructions`         | **The most important field.** Markdown instructions for the agent.       |
| `agent_id`             | Which agent persona runs this step.                                      |
| `allow_non_interactive`| Can the step run with no user in the loop.                                |
| `skip_policy`          | `never`, `if_outputs_exist`, or `manual`.                                |
| `on_failure`           | `retry`, `skip`, or `fail` (default).                                    |
| `max_retries`          | Auto-retry count.                                                        |
| `tool_ids`             | Tools available in this step (merged with workflow base).                |
| `skill_ids`            | Skills injected (merged with workflow base).                             |
| `mcp_server_ids`       | MCP servers connected (merged with workflow base).                       |
| `mount_repositories`   | Mount the project's Git repos under `/workspace/repo/`.                  |
| `depends_on_step_ids`  | DAG dependencies — enables parallel execution.                           |
| `preferred_model`      | LLM model override for this step.                                        |
| `input_asset_specs`    | Documented expected inputs (informational).                              |
| `output_asset_specs`   | Documented expected outputs (informational).                             |

## DAG and parallelism

A Step with `depends_on_step_ids: []` can start as soon as the workflow
run begins. Steps with dependencies wait until *all* listed
prerequisites complete successfully. Sibling steps that share no
dependency relationship run **in parallel**, each in its own container.

```
       ┌── Step B (lint)  ─┐
Step A ┤                   ├── Step D (merge)
       └── Step C (test)  ─┘
```

Aixle Flow uses **Temporal** to orchestrate this — runs survive process
restarts, retries are durable, and you can attach to a long-running
workflow from a fresh page reload.

## SubSteps

Inside a Step, the agent can mark progress milestones via the
`mark_sub_step` tool. SubSteps are **not** separate sessions — they're
checkpoints inside one container session. Use them when you want
visible progress for a long step (e.g. "1/5: scanned codebase",
"2/5: drafted plan"…).

## Execution flow

```
WorkflowRun  (pending → running → completed | failed)
├── StepRun 1                      ← one container
│   ├── TerminalSession
│   ├── SubStepRun 1.1 → 1.2 → 1.3
│   └── Produces: WorkflowRunAssets
├── StepRun 2  (waits on StepRun 1 if depends_on_step_ids)
└── StepRun 3
```

A `WorkflowRun` can be triggered by:

- a column binding (auto or manual),
- the **Trigger workflow** button on a task,
- the workflow's "Run" button outside the board,
- a schedule, a Slack message, or an inbound webhook,
- the API (`POST /company/projects/:project_id/workflow_runs`).

> **info** All of these flow through one event pipeline, and each off-board trigger carries a `subject_policy` deciding whether the run gets a board task. See [Triggers and Gates](/docs/triggers-and-gates) for the full model — including why a CI **gate** is not a trigger.

## Approval gates and human-in-the-loop

For a step that should pause for a human:

1. Set `allow_non_interactive: false` on the step.
2. The container starts but the agent waits for explicit approval.
3. The UI shows an **Approve / Retry / Skip** control on the step run.

The API endpoints behind those buttons:

- `POST /company/projects/:id/workflow_runs/:run_id/approve_step`
- `POST /company/projects/:id/workflow_runs/:run_id/retry_step`
- `POST /company/projects/:id/workflow_runs/:run_id/skip_step`

## Assets in and out

Three sources of input assets, all merged additively:

1. **Workflow base assets** (`workflow.config.base_asset_ids`) — always.
2. **Run-time assets** (`workflow_run.input_asset_ids`) — chosen when
   the run starts.
3. **Board task assets** — when triggered from a card.

Everything lands under `/workspace/assets/`. Agents write outputs to
`/workspace/outputs/` — those files become `WorkflowRunAssets` you can
download from the UI or via `GET /api/v1/projects/:id/workflow_runs/:run_id/workflow_run_assets`.

## Aixle Builder

Building a workflow by hand is rare in practice. The **Aixle Builder**
is an in-app conversational agent: describe your process in plain
language, it generates the workflow, steps, instructions, and resource
links for you. Open it from the project sidebar (Workflows → "Build with AI").

## Gotchas

- **A step that needs the codebase needs both** `mount_repositories: true`
  *and* a project with at least one repository configured. The flag
  alone does nothing if no repo is configured.
- **`if_outputs_exist`** skip policy compares asset filenames against
  `output_asset_specs`. Rename a spec and previously-skipped steps will
  re-run.
- **Parallel steps share the workflow run** but not their containers —
  they cannot read each other's `/workspace/` directly. Use
  `output_asset_specs` to hand artifacts forward.
