# Agents

An Agent in Aixle Flow is two things layered together:

- A **persona** — a system-prompt-level definition (who the agent *is*,
  how it communicates, what principles it follows).
- A **runtime** — the actual LLM CLI that runs inside the container.

You can mix and match: the same "Code Reviewer" persona can run on top
of Claude Code, Cursor CLI, Codex CLI, or Gemini CLI.

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

The persona runs on top of one of four LLM CLIs — `claude_code`,
`cursor_cli`, `codex`, or `gemini_cli`. Each runs in its own Docker
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
│   └── <task assets, if board-triggered>
├── repo/               ← Git repositories the step selected
│   └── <repo_name>/    ← shallow clone, default branch, full .git
└── references/         ← reference docs (only in Aixle Builder sessions)
```

When a step selects repositories, the platform also injects an authenticated
GitHub installation token — the agent can `git push`, open PRs, and trigger CI.

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
