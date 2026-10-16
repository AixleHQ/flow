# Agents

An Agent in Aixle Flow is two things layered together:

- A **persona** — a system-prompt-level definition (who the agent *is*,
  how it communicates, what principles it follows).
- A **runtime** — the actual LLM CLI that runs inside the container.

You can mix and match: the same "Code Reviewer" persona can run on top
of Claude Code, Cursor CLI, Codex CLI, Gemini CLI, Antigravity CLI, Grok CLI, or Kiro CLI.

## Persona fields

| Field                  | Description                                                |
| ---------------------- | ---------------------------------------------------------- |
| `name`                 | snake_case identifier.                                     |
| `title`                | Display name in the UI.                                    |
| `persona`              | Core system prompt — who the agent IS.                     |
| `communication_style`  | HOW the agent communicates.                                |
| `principles`           | Guiding constraints — non-negotiable rules.                |
| `source`               | `custom` or `bmad_import` (BMAD methodology import).       |

The system prompt the LLM actually sees is `persona + communication_style + principles`,
in that order.

## Runtimes

The persona runs on top of one of seven LLM CLIs — `claude_code`,
`cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`, or `kiro_cli`. Each runs in its own Docker
image and needs its own per-user credentials, configured on the
**Profile** page. The full runtime table, credential requirements, and
cost-tracking notes live on the dedicated Runtimes page.

## The container the agent runs in

When a step executes, the platform spins up a fresh container with this
layout:

```
/workspace/
├── outputs/            ← agent writes deliverables here
├── assets/             ← pre-loaded input files (read-only-ish)
│   ├── <workflow base assets>
│   ├── <run-time assets>
│   └── <outputs of Run-after steps>
├── repo/               ← Git repositories the step selected
│   └── <repo_name>/    ← the repository's source branch checked out, every branch fetched
└── references/         ← reference docs (only in Aixle Builder sessions)
```

A checkout of a connected repository (GitHub, GitLab or Azure DevOps) carries
every branch and the full commit history, so an agent can find and diff work
already in flight; the contents of other revisions download the first time they
are needed. A public repository cloned anonymously is the default branch only. `git fetch`, `git push` and `gh` authenticate
on every call with a short-lived token narrowed to that one repository, and
nothing is stored in the container — the agent can push, open PRs and trigger
CI as far as the connection's GitHub permissions allow.

## How context is built

Every session's context is assembled by an ordered chain of builders:

1. **CriticalRules** — non-negotiable system instructions.
2. **AgentRole** — persona + communication_style + principles.
3. **SessionInfo** — session metadata, mode, runtime, model.
4. **Workspace** — filesystem layout and key locations.
5. **WorkflowContext** *(workflow runs only)* — step instructions, previous outputs.
6. **BoardContext** *(board-triggered runs only)* — task details.
7. **Tools** — available tools with JSON schemas.
8. **Resources** — skills, MCP servers, repositories.
9. **BmadMethod** *(if enabled)* — BMAD methodology framework.
10. **OutputRules** — output formatting expectations.

This is why the same persona can produce very different output
depending on whether it was triggered from a board card vs. a manual
workflow run — the context layers differ.

## Resource resolution (additive merge)

For each step, the platform computes the effective set of tools,
skills, MCP servers, and repositories by **adding** three layers:

1. Workflow base resources (`workflow.config.base_*_ids`).
2. Step-specific resources (`step.*_ids`).
3. Project-level resources, if `inherit_all_project_resources: true`.

Duplicates are deduplicated by ID. There is no subtraction layer —
build narrowly and add up.

## Troubleshooting

| Symptom                                                       | Likely cause                                                                                |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Step starts then immediately fails with "no credentials"      | The runtime's credentials aren't configured for the user who triggered the run.             |
| Agent has no access to the codebase                           | No repository is selected on the step, the workflow, or the run.                            |
| Agent can't reach an MCP server                               | MCP server credentials missing in **Config Items**, or wrong `transport`.                   |
| Container hangs in "pulling image"                            | Run `make build-agents` to rebuild the runtime images locally.                              |
| `cost_cents` is `null` on a finished session                  | The runtime didn't emit usage events. Check the session logs in **Admin → Session Logs**.   |

For how to write the instructions a step gives its agent, see the [Prompt guide](/docs/prompt-guide).

## Recoverable context and verified completion

Workflow notes in the initial context are previews. A shortened step note carries
a `get_step_result(step_run_id: …)` call; a sub-step reference also supplies
`sub_step_run_id`. The tool reads only the current workflow run and returns the
full original note or selected sub-step data. Read that source before relying on
a shortened preview. A top-level result also lists sub-step IDs for discovery.

Structured data is shown as complete JSON only when it fits the preview. Larger
objects are omitted with a full-read reference. Over-budget compression can
remove inline data, but leaves the recovery reference. This is not a guarantee
that the whole session fits a provider's context window.

For board comments, use `board_list_comments(task_id: …)` and follow `has_more`
with `offset + comments.length`. Pages default to 25 comments and are capped at
100. Results are ordered by creation time and ID, newest first. Filters apply
before counting and paging. Each body is a preview of at most 400 characters;
`body_truncated` and `body_length` identify shortened text. Read the original
with `board_get_comment(task_id: …, comment_id: …)`. A recent comment is not
automatically an approved replacement for an older decision. The legacy
`board_get_comments` array response is unchanged.

In unattended mode, the agent may make minor, reversible assumptions and must
document them. It must consult available sources when essential requirements are
missing. If a required fact cannot be verified or a conflict prevents completion,
it must record the blocker and call `fail_session`, rather than invent a decision
or wait for a human who is not present. These are instructions, not a measured
guarantee about an LLM's behavior.

### Opt-in completion receipts

Use the personal MCP `update_workflow` tool with
`completion_evidence_required: true` to require verification receipts for the
workflow's unattended sessions. `get_workflow` reports the flag; setting it to
`false` disables it. Advanced session creation can also require receipts with
boolean `metadata.completion_evidence_required: true`. Enforcement is off by
default; a workflow requirement cannot be disabled by session metadata.

When enabled, `finish_session` needs `evidence_execution_ids`: up to 20 IDs of
recorded tool executions from the current session, each completed with exit code
zero. A verification wrapper can check files, commits or run tests; its async call
returns an execution ID, and `read_tool_result` retrieves its status and outputs.
A shell command run directly by the CLI does not automatically create a recorded
`ToolResult`. Attach a suitable verification tool before enabling the requirement.

Unknown, failed, pending, expired and other-session executions are rejected before
changing the step note or completing the session. Accepted IDs, tool names, exit
codes and verification times are stored in `metadata.completion_evidence`; raw
outputs are not copied there. Supplying evidence also validates it when enforcement
is off. A success note alone cannot satisfy an enabled requirement.

A receipt proves that Flow recorded a successful execution. It does not prove that
an arbitrary command checked the correct acceptance criterion or that every claim
in a report is true. Existing output specifications and review still apply.
