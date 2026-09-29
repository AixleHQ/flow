# Aixle Platform — System Reference

> The platform model for AI agents that configure Aixle: the Aixle Builder (inside
> a builder session) and callers of the personal MCP server. Tool names below are
> the personal-MCP / builder tool names. `test/references/aixle_system_reference_test.rb`
> checks this file against the code, so a renamed field or runtime fails CI here.

---

## 1. Overview

Aixle runs business processes as **workflows**: ordered **steps**, each executed
by an AI agent in its own container, launched by hand or by a **trigger** (a card
entering a board column, a Slack message, a schedule, a webhook, a custom event).

```
Company
└── Projects
    ├── Board ─ BoardColumns ─ BoardTasks (comments, attachments, gates)
    ├── Workflows ─ Steps ─ SubSteps
    │   ├── ColumnWorkflowBinding (column trigger) / TriggerBinding (other triggers)
    │   └── WorkflowRuns ─ StepRuns ─ TerminalSession (the container)
    ├── Agents, Tools, Skills, MCP servers, Repositories, Config items
    └── Assets
```

**Scoping.** Workflows, agents, custom tools, skills, MCP servers, repositories
and config items all belong to exactly one **project**. Nothing is shared between
projects; to reuse a workflow elsewhere, `duplicate_workflow` copies it. The
exceptions: platform tools (code-defined, available to every project), internal
MCP servers, and **assets**, which can also be company-wide.

---

## 2. Board

One board per project, created by `setup_board` from a preset — `simple_kanban`
(3 columns), `dev_team` (7) or `full_sdlc` (19). A new project has no board.

**BoardColumn**: `name`, `position`, `purpose` (what the stage means — shown to
agents). A column with tasks cannot be deleted.

**BoardTask**: `title`, `description` (markdown), `task_type` (epic, story, bug,
not_specified), `priority` (low, medium, high, critical), `tags`, `assignee_id`,
`parent_task_id` (one level: epic → story), `archived_at`. Tasks carry threaded
comments (with tags such as `tech_design`, `code_review`), file attachments, and
gates.

**Gate**: blocks a column's automatic trigger until an external check finishes.
Types: `github_checks_completed`, `github_workflow_completed`,
`gitlab_pipeline_completed`, `azure_devops_build_completed`,
`azure_devops_pr_policies_satisfied`. Status: pending → resolved, or stale when
the provider never reported (stale stops blocking). Step agents open gates with
`board_create_gate`; CI webhooks resolve them.

---

## 3. Workflows

**Workflow**: `name` (unique in the project), `description`, `config`:

| `config` key | Meaning |
|---|---|
| `base_tool_ids` | tools every step gets |
| `base_skill_ids` | skills every step gets |
| `base_mcp_server_ids` | MCP servers every step gets |
| `base_asset_ids` | files every step gets |
| `base_repository_ids` | repositories every step gets |
| `base_config_item_ids` | secrets/variables every step may read |
| `inherit_all_project_resources` | fall back to every project tool, skill, MCP server and repository |

Unknown config keys are rejected.

**Step** — one agent session, one container:

| Field | Meaning |
|---|---|
| `name`, `position` | |
| `instructions` | the task brief (markdown) — the most important field |
| `agent_id` | the persona that runs it (none: default persona) |
| `allow_non_interactive` | may run unattended; required for unattended triggers |
| `skip_policy` | `never`, `if_outputs_exist`, `manual` |
| `on_failure` | `retry`, `skip`, `fail` |
| `max_retries` | automatic retries |
| `depends_on_step_ids` | DAG: runs after these; independent steps run in parallel |
| `tool_ids`, `skill_ids`, `mcp_server_ids` | capabilities for this step |
| `asset_ids` | files for this step |
| `repository_ids` | repositories cloned for this step |
| `config_item_ids` | secrets/variables this step may read |
| `preferred_model` | model id override |
| `required_agent_runtime` | pin to one runtime (see §5) |
| `bmad_enabled` | install the BMAD Method in the step's container |
| `input_asset_specs`, `output_asset_specs` | `[{name, description}]` — what the step expects and produces |

Every id on a step or a workflow's config must belong to the workflow's project
(platform tools, internal MCP servers and company assets excepted); the save is
rejected otherwise. On an update, an id list **replaces** the stored one.

**SubStep**: `name`, `instructions`, `position`, `required` — a checklist inside
one session, ticked off by the agent with `mark_sub_step`.

**WorkflowRun** mode: `interactive`, `non_interactive`, `mixed`. Each step gets a
StepRun and a TerminalSession; files the step writes to `/workspace/outputs/`
become run assets.

---

## 4. Triggers

A workflow only starts when something launches it.

**Column trigger** (`ColumnWorkflowBinding`): a card entering the column starts
the workflow. One per column. `trigger_mode` `auto` (on entry) or `manual` (a
button); `cooldown_seconds` (default 5). An auto trigger waits while the task has
a pending gate or an active run.

**Other triggers** (`TriggerBinding`), created with `create_workflow_trigger`
`kind`:

| kind | fires on |
|---|---|
| `slack` | a Slack message (needs the Slack integration) |
| `schedule` | cron — `schedule_config: {cron, timezone}` |
| `webhook` | an inbound HTTP call; the response carries the URL and a secret shown once |
| `event` | a custom platform event |

Fields: `name`, `event_type`, `filter_predicate` (JSON the event must contain;
supports `{"op", "value"}` operators and dot-paths), `subject_policy` (`none`,
`existing_task`, `create_task`) with `subject_column_id` and
`subject_title_template`, `trigger_mode`, `cooldown_seconds` (default 0),
`enabled`, `notify_on_failure`.

Rules enforced on save:
- Slack, schedule, webhook and event triggers need `allow_non_interactive` on
  every step.
- `schedule` needs a cron expression; give a timezone too, or it runs in UTC and
  drifts an hour across daylight saving.
- `create_task` needs `subject_column_id`.

---

## 5. Agents and runtimes

**Agent**: `name`, `title`, `icon`, `persona` (who it is), `communication_style`,
`principles`, `source` (`custom`, `bmad_import`). The three texts form the
agent's system prompt.

**Runtimes** — the CLI that executes a session: `claude_code`, `cursor_cli`,
`codex`, `gemini_cli`, `antigravity_cli`, `grok`, `kiro_cli`. Each user connects
their own credentials per runtime; a step can pin one with
`required_agent_runtime` (`claude_code`, `cursor_cli`, `codex`, `gemini_cli`,
`antigravity_cli`).

---

## 6. Capabilities

**Tools.** Platform tools are defined in code and grouped by tag (board, slack,
azure_devops, coder, …); some appear only when their integration is connected.
Custom tools are project docker-image tools (`docker_image`, `command`,
`input_schema`, `required_config_items`). Prefer an MCP server for anything
external.

**Skills**: reusable instruction packs (SKILL.md) — `name`, `title`,
`description`, `content`, `origin` (`registry` from skills.sh, or `manual`).
`search_skill_registry` → `get_registry_skill` → `install_skill`, or
`create_skill`.

**MCP servers**: `name`, `description`, `transport` (`http`, `sse`, `stdio`),
`url` or `command` + `args`, `headers` / `env`, `auth_type` (`none`, `static`,
`oauth`), `credential_scope` (`shared`, or `per_user` — each user signs in), and
`enabled`. Servers installed from the connector catalog
(`search_connector_catalog` → `get_connector` → `install_connector`) remember
their connector and version. Header and env values reference secrets as
`config_item:NAME`.

**Repositories**: GitHub (App installation or personal access token), GitLab or
Azure DevOps through an integration, or a public URL cloned read-only. Fields:
`full_name`, `source_branch`, `purpose`, `description`, `is_private`.

**Config items**: `secret` (stored encrypted) or `variable`. Values are entered
by users in the UI and never returned by any tool.

**Integrations**: `github`, `gitlab`, `slack`, `azure_devops`, `coder`, `linear`.
Users connect them in the browser (`get_integration_setup_url`).

**Assets**: project or company files. Board-task attachments are separate
files that live on the task.

---

## 7. How a step executes

```
/workspace/
├── outputs/          deliverables — collected as run assets
├── assets/           input files (read-only)
├── repo/<name>/      cloned repositories, authenticated git
└── references/       reference docs (builder sessions only)
```

**Files** in `assets/`: the workflow's `base_asset_ids` + the step's
`asset_ids` + files chosen when the run starts. Board-task attachments are not
mounted; the step agent lists them with `board_get_task_assets`.

**Repositories**: the run's own pick wins; otherwise the step's `repository_ids`
plus the workflow's `base_repository_ids`; only when nothing names one and
`inherit_all_project_resources` is on does the step get every project
repository. How the run started never changes this.

**Tools, skills, MCP servers**: workflow base + step (+ every project resource
with `inherit_all_project_resources`). The internal `aixle-tools` MCP server is
always connected: session lifecycle, sub-steps, board tools, and integration
tools (Slack, Azure DevOps, Coder) when connected.

**Secrets**: the step reads its config items with `get_config_item`; MCP
credentials are resolved from config items at launch.

**Context**: the platform writes the agent's instructions file (CLAUDE.md,
AGENTS.md, GEMINI.md, … per runtime) with: the agent persona, session and
workspace facts, the step's instructions and sub-steps, earlier steps' notes,
the board task (board-triggered runs), available tools and resources, attached
config items, BMAD guidance when enabled, and — for unattended runs — the rule
that the session ends only through `finish_session` / `fail_session`.

**Between steps**: `finish_session`'s note and sub-step `data`/`note` reach later
steps; outputs become run assets; on board-triggered runs every step shares the
task, so tagged comments carry structured hand-offs.

---

## 8. Step-agent tools (inside a running step)

- Lifecycle: `finish_session(note)`, `fail_session(reason)`
- Sub-steps: `list_sub_steps`, `mark_sub_step`
- Board: `board_get_board_info`, `board_list_tasks`, `board_get_task`,
  `board_create_task`, `board_update_task`, `board_move_task`,
  `board_add_comment`, `board_get_comments`, `board_manage_tags`,
  `board_attach_asset`, `board_get_task_assets`, `board_list_members`,
  `board_create_gate`, `board_list_gates`
- Files: `promote_asset`, `share_asset`
- Secrets: `get_config_item`
- Async tools: `read_tool_result`
- When connected: `slack_*`, `azure_devops_*`, `coder_*`, `refresh_github_token`
