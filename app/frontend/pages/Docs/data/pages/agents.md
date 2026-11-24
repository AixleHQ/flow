# Agents

An Agent in Aixle Flow is two things layered together:

- A **persona** — a system-prompt-level definition (who the agent *is*,
  how it communicates, what principles it follows).
- A **runtime** — the actual LLM CLI that runs inside the container.

You can mix and match: the same "Code Reviewer" persona can run on top
of Claude Code, Cursor CLI, Codex CLI, Gemini CLI, Antigravity CLI, Grok CLI, Kiro CLI, or GitHub Copilot CLI.

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

The persona runs on top of one of eight LLM CLIs — `claude_code`,
`cursor_cli`, `codex`, `gemini_cli`, `antigravity_cli`, `grok`, `kiro_cli`, or `copilot_cli`. Each runs in its own Docker
image and needs its own per-user credentials, configured on the
**Profile** page. The full runtime table, credential requirements, and
cost-tracking notes live on the dedicated [Runtimes](/docs/runtimes) page.

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

A checkout of a connected repository (GitHub, GitLab, Bitbucket or Azure DevOps) carries
every branch and the full commit history, so an agent can find and diff work
already in flight; the contents of other revisions download the first time they
are needed. A public repository cloned anonymously is the default branch only. `git fetch`, `git push` and `gh` ask the platform
for a credential on every call — for a GitHub App connection, a short-lived token
narrowed to that one repository — and nothing is stored in the container: the
agent can push, open PRs and trigger CI as far as the connection's permissions allow.

## How context is built

Every session's context is assembled by an ordered chain of builders:

1. **CriticalRules** — non-negotiable system instructions.
2. **AixleBuilder** *(Aixle Builder sessions only)* — the builder's role, a snapshot of the project, and its tool catalog.
3. **AgentRole** — persona + communication_style + principles.
4. **SessionInfo** — session metadata, mode, runtime, model.
5. **Workspace** — filesystem layout and key locations.
6. **WorkflowContext** *(workflow runs only)* — step instructions, previous outputs.
7. **TrackerContext** *(runs a tracker event started)* — the tracker and the issue that started the run.
8. **PullRequestContext** *(runs a pull-request event started)* — the review or comment that started the run, and the pull request's branch.
9. **WebhookContext** *(runs an inbound webhook started)* — the file holding the request's JSON body, the run's input.
10. **BoardContext** *(runs about a board task)* — task details.
11. **Tools** — the shell tools, the MCP servers, and the names of the available tools. Each runtime gets a tool's description and parameters from the MCP server itself.
12. **Resources** — repositories, input assets, skills.
13. **ConfigItems** *(when config items are attached)* — the names of the secrets and variables the agent may read with `get_config_item`.
14. **BmadMethod** *(if enabled)* — BMAD methodology framework.
15. **OutputRules** — output formatting expectations.
16. **SessionCompletion** *(automatic sessions only)* — the session ends only when the agent calls `finish_session` or `fail_session`.

This is why the same persona can produce very different output
depending on whether it was triggered from a board card vs. a manual
workflow run — the context layers differ.

## Resource resolution (additive merge)

For each step, the platform computes the effective set of tools,
skills and MCP servers by **adding** three layers:

1. Workflow base resources (`workflow.config.base_*_ids`).
2. Step-specific resources (`step.*_ids`).
3. Project-level resources, if `inherit_all_project_resources: true`.

Duplicates are deduplicated by ID. There is no subtraction layer —
build narrowly and add up.

Repositories are not added up: a pick on the run, the workflow's base or the
step is the whole set, and the project's repositories are used only when none
of them names one and the workflow has `inherit_all_project_resources`.

## Troubleshooting

| Symptom                                                       | Likely cause                                                                                |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Step starts then immediately fails with "no credentials"      | The runtime's credentials aren't configured for the user who triggered the run.             |
| Agent has no access to the codebase                           | No repository is selected on the step, the workflow, or the run.                            |
| Agent can't reach an MCP server                               | MCP server credentials missing in **Config Items**, or wrong `transport`.                   |
| Container hangs in "pulling image"                            | Run `make build-agents` to rebuild the runtime images locally.                              |
| `cost_cents` is `null` on a finished session                  | The runtime didn't emit usage events. Check the session logs in **Admin → Session Logs**.   |

For how to write the instructions a step gives its agent, see the [Prompt guide](/docs/prompt-guide).
