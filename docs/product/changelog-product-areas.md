# Aixle Flow Product Snapshot — Changelog Taxonomy

> Deliverable for issue #551. A user-facing map of Aixle Flow as it exists
> today, frozen as the changelog taxonomy: after a release, every user-visible
> change is tagged with one **product area** from the tables below, so each
> release reads as a change to a named part of the product — not as a list of
> tickets.
>
> **Snapshot date:** 2026-08-17. Area names are verified against the product
> UI (sidebar labels and page titles), not internal engineering names.

## What Aixle Flow is

Aixle Flow is the team layer on top of personal AI coding agents. A person puts
work on a board. An agent picks it up, does the work, and the team sees the
run, the output, and the cost — without anyone opening a terminal.

A **Company** is the workspace. Inside it, each **Project** has one board. Move
a card into a column that is bound to a workflow, and the workflow starts. A
workflow is a sequence of steps; each step is one agent doing one job. Steps
can run in parallel, wait for each other, retry, or pause for a human. Every
run leaves a trail: status, log, artifacts, tokens, and cost.

Supported agent runtimes: Claude Code, Cursor CLI, Codex, Gemini CLI, Grok.

## Product areas (changelog taxonomy)

Use the names in **bold** in changelog entries. They match what people see in
the product — or, where no single sidebar label exists (sign-in, triggers),
they name a flow users would recognize.

### Workspace

| Area | What it covers |
| --- | --- |
| **Companies & projects** | Workspaces, switching between companies, creating and listing projects |
| **Sign-in & onboarding** | Login, invitations, first-run setup: role, language, connecting an agent |
| **Profile** | Personal agent credentials (connecting a runtime account), personal usage, personal access so Aixle can be used from an external agent |

### Project — Work

| Area | What it covers |
| --- | --- |
| **Overview** | Project home: activity, task distribution, spend, workflow run status |
| **Tasks** | The board: columns, cards, subtasks, comments, attachments, waits, activity. Column → workflow binding (auto or manual). Board templates (Simple Kanban, Dev Team, Full SDLC) offered on an empty board |
| **Workflows** | Named processes made of steps: instructions, which agent runs, dependencies, on-failure behavior (fail / retry / skip), human approval, inputs/outputs. Publishing and duplicating |
| **Triggers & gates** | When a workflow starts (task enters column, manual run, schedule, Slack message, inbound webhook) and what can pause a run (waiting on a check or a person) |
| **Runs** | Workflow runs, live and past: step timeline, parallel waves, approve / retry / skip, cost |
| **Sessions** | Individual agent sessions: status, log, cost, tokens, artifacts |
| **Assets** | Files the team uploads and files agents produce; versioning and review |

### Project — Resources

| Area | What it covers |
| --- | --- |
| **Agents** | Personas (who the agent is, how it talks, what rules it follows). The same persona can run on any supported runtime |
| **Wrappers** | Custom tools the team writes so agents can call services that have no connector |
| **Skills** | Reusable know-how installed from a catalog or written by hand |
| **Connectors** | External tool servers agents can call, from a catalog or added by hand |
| **Repositories** | Linked Git repos the agent can work in and push to |
| **Integrations** | GitHub, GitLab, Linear, and similar connections |

### Project — Admin

| Area | What it covers |
| --- | --- |
| **Secrets & Variables** | Credentials and config values agents and connectors use |
| **Members** | Who is on the project and with what access (roles: Admin, Employee, Viewer) |
| **Analytics** | Spend, sessions, tokens, success — by project, agent, and source |
| **Settings** | Project name, language, archive, delete |

### Build with AI

| Area | What it covers |
| --- | --- |
| **Aixle Builder** | Describe a process in plain language; the product creates workflows, steps, tools, and board setup. (Sidebar entry point is labeled "AI Builder" / "Build with AI"; the feature's pages are titled "Aixle Builder" — this taxonomy uses **Aixle Builder**) |

### Company library & monitoring

| Area | What it covers |
| --- | --- |
| **Workflow Catalog** | Shared workflows the team can copy into a project |
| **Company analytics** | Spend and activity across projects (admins) |
| **Company sessions** | Cross-project run visibility (admins) |
| **Company assets** | Workspace-level files (admins) |
| **Company members** | Who belongs to the company |

### Help

| Area | What it covers |
| --- | --- |
| **Docs** | The in-product documentation, linked from the public site as **Documentation** |

## How the pieces fit (for changelog writers)

Tasks (board) → card enters a bound column → Workflow starts → each Step is one
Agent session → results, status, and cost come back to the board, to Runs, and
to Sessions.

Agents do not work in a vacuum. A run can receive: the card (title,
description, comments, files, column purpose), workflow instructions, skills,
wrappers, connectors, repositories, and secrets.

## Changelog rules

1. One entry maps to **one product area** from the tables above. If a change
   spans two areas, split it or pick the one users notice first.
2. Write for a user who never opens a terminal. Say what they can do now, not
   how it was built.
3. Preferred shape: **Added / Changed / Fixed / Removed** × product area, e.g.
   `Added — Tasks: attach files directly to a card`.
4. Do not mention implementation. If the only change is internal and users
   cannot see it, it does not belong in the product changelog.
5. Keep this snapshot as the baseline. When a release adds a new area (a new
   nav item or a new first-class object), update this snapshot in the same
   change as the changelog entry.

## Out of scope

Internals, APIs, ops, and anything not visible in the product.
