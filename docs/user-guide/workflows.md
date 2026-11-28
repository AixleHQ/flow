# Workflows

A Workflow is a DAG of Steps that together accomplish a business
process — a code review, a feature spec, a bug triage. Each Step is one
agent session in one container.

> The workflow builder names these levels differently from the API: a
> **Step** on this page is a **session** in the builder, and a **SubStep** is a
> **step** in the builder. The API, the MCP tools (`create_workflow_step`,
> `create_sub_step`) and the field names below keep `step` and `sub_step`.

## Anatomy of a Workflow

| Field                            | Description                                                                 |
| -------------------------------- | --------------------------------------------------------------------------- |
| `name`                           | Unique within its project.                                                   |
| `description`                    | What the workflow accomplishes.                                              |
| `config.base_tool_ids`           | Tools always available to every step in this workflow.                       |
| `config.base_skill_ids`          | Skills always injected into agent context.                                   |
| `config.base_mcp_server_ids`     | MCP servers always connected.                                                |
| `config.base_asset_ids`          | Files always pre-loaded into `/workspace/assets/`.                           |
| `config.base_integration_ids`    | Coder, Slack, Teams and Azure DevOps integrations every step may act through. Never inherited, see [Integrations of a session](#integrations-of-a-session). |
| `config.inherit_all_project_resources` | If true, the project's resources merge in additively; its repositories only when no level names one. |

A workflow has no mode of its own. Each run picks its `mode` when it starts:
**Fully automatic** (`non_interactive`), **Interactive** (`interactive`, approve
each step) or **Custom** (`mixed`, auto-run chosen per step).

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
| `on_failure`           | `retry`, `skip`, or `fail` (default). A step that stopped on its owner's agent quota is not retried — the same account would fail again. In a run a team handed out, a quota stop or a failed login hands the step to the team's next member whatever this says, without using a retry. |
| `max_retries`          | Times a failed step starts again when `on_failure` is `retry`: 1–10.     |
| `tool_ids`             | Tools available in this step (merged with workflow base). A step gets only the tools attached here or to the workflow, plus the session-lifecycle and sub-step tools. |
| `skill_ids`            | Skills injected (merged with workflow base).                             |
| `mcp_server_ids`       | MCP servers connected (merged with workflow base).                       |
| `repository_ids`       | Repos cloned under `/workspace/repo/` (merged with workflow base).       |
| `integration_ids`      | Integrations this step may act through, added to the workflow's (see [Integrations of a session](#integrations-of-a-session)). |
| `depends_on_step_ids`  | DAG dependencies — enables parallel execution.                           |
| `preferred_model`      | LLM model override for this step.                                        |
| `reasoning_effort`     | Reasoning effort the step's CLI runs at (`low`, `high`, …). Unset keeps the CLI's default. It needs an explicit `required_agent_runtime` and `preferred_model`: a level without either is refused, so clear the level with them. Only the levels that runtime takes for that model are accepted. The CLI may still lower or ignore a level the model doesn't support. |
| `input_asset_specs`    | Expected inputs. A required one is checked before the step starts; a missing one fails the step ("Required input missing"). Needed only for files picked when a run starts: an `@` reference is checked without one. |
| `output_asset_specs`   | Expected outputs. A required one is checked when the step ends; a missing one fails the step ("Output validation failed"). A name is the file's path under `/workspace/outputs/` (a `/workspace/…` prefix is dropped), or a glob such as `reports/*.md`; `dir/**` takes everything under `dir`. |

## Integrations of a session

A session gets only the integrations in its **integration set**. For a workflow
step the set is the workflow's **Integrations** list plus the step's own, the
integrations of the repositories attached to the step, and the integration the
run started from (the Slack or Teams install of the message that started it, or
the integration of the tracker that did). A set is never widened by
`inherit_all_project_resources`: an integration is access to an external account,
so each one is attached by hand.

Only Coder, Slack, Teams and Azure DevOps integrations can be attached. GitHub,
GitLab and Bitbucket are reached through repositories, trackers through the
project's trackers, and AWS through roles.

A tool that acts through an integration (the `coder_*`, `chat_*` and Azure
DevOps build tools) is served when it is attached **and** its provider's
integration is in the session's set. It takes an `integration_id`, which may be
left out when the set holds exactly one integration of that provider; with
several, leaving it out is an error that lists them. An id outside the set is
refused. The agent is told its integrations (id, name, provider) in its context.

An interactive session chooses its integrations in the new-session form, which
preselects the project's Coder integration, every Slack and Teams install the
project can see and its Azure DevOps connections. Over the API,
`POST /api/v1/terminal_sessions` takes `integration_ids`; **a session created
without it has no integrations.** Restoring a suspended session copies its set.
Over MCP, `list_integrations` lists what can be attached, and the workflow and
step tools take `base_integration_ids` and `integration_ids`.

Duplicating a workflow inside its project keeps its integrations; copying it to
another project drops them, and a template carries none: attach the receiving
project's own.

## DAG and parallelism

A Step with `depends_on_step_ids: []` can start as soon as the workflow
run begins. Steps with dependencies wait until *all* listed
prerequisites complete successfully. Sibling steps that share no
dependency relationship run **in parallel**, each in its own container.

Dependencies cannot form a cycle: saving a step that would end up waiting on
itself is rejected with the cycle spelled out. If a run is left with steps that
can never start, it fails with `failure_reason: unsatisfiable_dependencies`
instead of reporting completion.

```
       ┌── Step B (lint)  ─┐
Step A ┤                   ├── Step D (merge)
       └── Step C (test)  ─┘
```

A step's starting context summarizes only the steps it depends on, directly or
through others, each from its latest completed or skipped attempt. In the diagram,
Step D gets A, B and C; Step B gets only A, never C, which runs beside it.
For spec-first workflows and the context budget, see
[Token-efficient workflows](token-efficient-workflows.md).

Aixle Flow uses **Temporal** to orchestrate this — runs survive process
restarts, retries are durable, and you can attach to a long-running
workflow from a fresh page reload.

## SubSteps

SubSteps are what the builder shows as a session's steps. They are **not**
separate sessions — they're a checklist inside one container session. They
reach the agent as a numbered list under the Step's instructions, and the
agent marks each one with the `mark_sub_step` tool. Use them when you want
visible progress for a long step (e.g. "1/5: scanned codebase",
"2/5: drafted plan"…). Neither their order nor their `required` flag is
enforced at run time.

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
- the **Run workflow** button on a task,
- the workflow's "Run" button outside the board,
- a schedule, a Slack or Teams message, an inbound webhook, an event in a
  connected tracker, or a review or comment on a pull request,
- the API (`POST /company/:company_slug/projects/:project_id/workflow_runs`).

> All of these flow through one event pipeline, and each off-board trigger carries a `subject_policy` deciding whether the run gets a board task. See [Triggers and Gates](triggers-and-gates.md) for the full model — including why a CI **gate** is not a trigger.

## Approval gates and human-in-the-loop

For a step that should pause for a human:

1. Set `allow_non_interactive: false` on the step.
2. The container starts but the agent waits for explicit approval.
3. The UI shows an **Approve / Retry / Skip** control on the step run.

The API endpoints behind those buttons:

- `POST /company/:company_slug/projects/:id/workflow_runs/:run_id/approve_step`
- `POST /company/:company_slug/projects/:id/workflow_runs/:run_id/retry_step`
- `POST /company/:company_slug/projects/:id/workflow_runs/:run_id/skip_step`

## Assets in and out

Three sources of input assets, all merged additively:

1. **Workflow base assets** (`workflow.config.base_asset_ids`) — always.
2. **Run-time assets** (`workflow_run.input_asset_ids`) — chosen when
   the run starts.
3. **Outputs of every step it runs after** (`depends_on_step_ids`, followed through: a step after B, which runs after A, gets both), placed at `/workspace/assets/<name>`. When two of them wrote the same name, the nearest one's copy wins. The agent's context lists them.

Files attached to a board card are **not** mounted; the agent fetches them with `board_get_task_assets`.

Everything lands under `/workspace/assets/`. Agents write outputs to
`/workspace/outputs/` — those files become `WorkflowRunAssets` you can
download from the UI or via `GET /api/v1/projects/:id/workflow_runs/:run_id/workflow_run_assets`.

## References and the data-flow check

Typing `@` in a session's instructions inserts a reference to an asset, a declared
output, another session, an MCP server, a tool, a skill or a config item. It is stored
as a token with the row's id (`{{asset:12}}`, `{{output:45:summary.md}}`, `{{step:45}}`,
`{{mcp:7}}`, `{{tool:9}}`, `{{skill:4}}`, `{{config_item:3}}`), shown as a chip, and
replaced with the path or name when the session starts — a config item by its name
only, never its value. Picking an item attaches it, or adds Run after, when the session
would not otherwise get it. Duplicating a workflow or exporting it as a template carries the references.

The builder checks the whole workflow as you edit — references that no longer resolve,
outputs read from a session that does not run first, input and output names that cannot
match, braces nothing replaces — and lists what it finds under each session. Saving is
never blocked. A run that would fail for certain does not start, and `validate_workflow`
reports the same list.

## Saving, versions and the archive

Edits in the workflow builder stay in your browser until you press **Save** —
the header says *Unsaved changes* until you do, and leaving the page asks
first. One Save stores the whole workflow (its fields, every step and
sub-step) as one numbered **version**. Agents, skills, wrappers and MCP servers
are versioned the same way, one version per Save of their form.

- **History** (the clock icon on every workflow, agent, skill, wrapper and
  connector) lists the versions newest first: who saved each one — a person or
  the Aixle Builder acting for them — when, and what changed, compared with
  the version before it or with the current one.
- **Revert** puts an earlier version's content back and saves it as the newest
  version; nothing in the history is overwritten. The confirmation spells out
  what will change. MCP server secrets are never stored in a version, so a
  revert keeps the current header and env values — and one that moves the
  server to another address clears them, as an edit would.
- **If someone saved first**, your Save is refused rather than silently
  overwriting their change; reload to see it.
- **Archive** replaces delete. An archived entity leaves pickers and new
  sessions but keeps its history, and can be restored from the list screen's
  *Archived* view. Archiving is refused while a workflow still uses the entity.
  Restoring a workflow offers to switch back on the triggers archiving turned off.
- **Which version ran**: runs read the saved workflow at the moment each
  session launches, and the run page shows the version per session. A Save made
  while a run is in progress affects the sessions that have not started yet —
  the run page then says so.

## Changing a workflow that is in use: drafts

A Save goes live at once: every trigger and board column that starts the
workflow runs the new version from then on. To try a change first, work in a
**draft** — a copy of the workflow that only you start.

- **Edit in draft** in the builder's header opens one. Saving a workflow that
  triggers or columns start also asks first: **Save to live**, or **Save as
  draft** to put your unsaved edits into a new draft instead.
- The draft opens in the same builder, under the same workflow's address, with a
  banner saying so. Save it as often as you like; triggers and columns keep
  running the live version.
- **Test run** starts the draft like any run. Choose the custom mode in the run
  drawer to start each step yourself. The run page says it ran the draft and
  gives the draft's own version numbers (`draft v2`), which are not the live
  workflow's. In **Sessions & Runs** a draft's test runs are listed under the
  workflow, named `<workflow> (draft)`.
- **What will change** compares the draft with the live workflow.
- **Apply** makes the draft the live workflow, as one new version, and closes
  the draft. The version history marks that version **Applied from draft**. If
  someone saved the live workflow after the draft was made, Apply says so first:
  **Apply anyway** replaces their change too.
- **Discard draft** closes it and leaves the live workflow as it was.

> A test run is a real run: its agents push, comment and message with your credentials. The only thing it leaves out is the workflow of a board column it moves a card into, which does not start.

A workflow has at most one draft, shared by everyone who can edit the workflow.
Triggers belong to the live workflow, so a draft has none. Agents, skills,
wrappers and connectors are not part of a draft: editing one changes it for the
live workflow too. Over the personal MCP the same flow is
`create_workflow_draft`, `get_workflow_draft_diff`, `apply_workflow_draft` and
`discard_workflow_draft`; `list_workflow_runs` and `get_workflow_run` mark a
test run of a draft with `draft_test`.

## Aixle Builder

Building a workflow by hand is rare in practice. The **Aixle Builder**
is an in-app conversational agent: describe your process in plain
language, it generates the workflow, steps, instructions, and resource
links for you. Open it from the **Build with AI** card in the project sidebar.

## Gotchas

- **A step gets code only if some level names a repository** — the step's
  own `repository_ids`, the workflow's `base_repository_ids`, or the run's
  one-off override. An explicit pick anywhere wins outright; the project's
  full set is used only when nothing names one and the workflow has
  `inherit_all_project_resources`. How the run started never matters.
- **`if_outputs_exist`** skip policy compares asset filenames against
  `output_asset_specs`. Rename a spec and previously-skipped steps will
  re-run.
- **Parallel steps share the workflow run** but not their containers —
  they cannot read each other's `/workspace/` directly. Use
  `output_asset_specs` to hand artifacts forward.
- **An automatic step ends only when its agent calls `finish_session` or
  `fail_session`.** A Kiro, Copilot CLI or Antigravity agent that ends its turn without either gets a
  reminder typed into its terminal a minute or two later, up to 3 times. If it
  stops a fourth time, the step fails with a message saying so. Nothing is typed
  while someone has typed into the session's terminal in the last 10 minutes.
  A step whose terminal stays unchanged fails 30 to 35 minutes later. For Kiro,
  "unchanged" means its screen, even while the terminal keeps redrawing it; for
  other runtimes, that the terminal sent no output at all.

Writing the instructions themselves: see the [Prompt guide](prompt-guide.md).
