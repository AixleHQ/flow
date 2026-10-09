# What Flow Is

Aixle Flow is the team layer on top of personal AI coding agents. One person
puts work on a board. An agent picks it up, does the work, and the whole team
sees the run, the output, and the cost — without anyone opening a terminal.

If you are installing or operating Flow, read the [User Guide](/docs/user-guide)
instead. This section is for people who *use* the product.

## The loop

```
 a card moves · Run · a schedule ──► Workflow ── step by step ──► Agent
 Slack or Teams · a tracker issue                                   │
 a webhook                                                          │
  ▲                                                                 │
  └────────── status, files, comments and cost come back ◄──────────┘
```

1. Something starts a workflow. Most often a card moves into a column that is
   bound to it — the workflow starts automatically, or from a button if the
   column is set to manual. It can also start on a schedule, from a Slack or
   Teams message, from an issue in a connected tracker, from a webhook, or from
   **Run**. See [Triggers & gates](/docs/starting-work).
2. Each step of the workflow is one agent session doing one job. Independent
   steps run at the same time. When the project is at its limit, a session
   waits its turn in the [session queue](/docs/session-queues).
3. The agent works under the credential of the person the run belongs to: the
   card's assignee, else whoever moved the card or pressed **Run**; for a
   schedule, a message, a webhook or a tracker event, whoever set up the
   trigger.
4. Results come back to where the work started. A card gets status, comments
   and files; a Slack or Teams thread gets a status card that follows the run;
   a tracker issue gets a comment if the run fails. Files are kept in Assets,
   the full trail in Sessions & Runs, and cost in Analytics.

Nothing in that loop asks you to run a command yourself. Your part is writing
the card, deciding the process once, and reviewing what comes back.

## Company, project, profile

Flow has exactly three levels, and almost every question about "where does this
setting live?" is answered by one of them.

| Level | Holds | Example |
| --- | --- | --- |
| **Company** | The shared workspace: projects, members, catalog, company-wide analytics | Your organisation |
| **Project** | One board, its workflows, and its own resources and access | "Billing service" |
| **Profile** | What is personal: your agent credentials, your usage, your personal access | You |

You can belong to more than one company. A switcher on the far left moves you
between them; each company has its own projects, members, and numbers.

## What actually runs the work

Flow does not ship its own model. It runs the agent products people already
use, each in an isolated container:

- Claude Code
- Cursor CLI
- Codex
- Gemini CLI
- Antigravity CLI
- Grok
- Kiro CLI

An agent runs under a credential *a person connected*, which is why
[getting started](/docs/getting-started) begins with connecting one. A persona
you define (see [Agent personas](/docs/personas)) is not tied to a product —
the same persona can run on any of them.

## Where things live

- **Work** — [Tasks](/docs/tasks), [Workflows](/docs/running-workflows),
  [Sessions & Runs](/docs/sessions-and-runs), [Assets](/docs/assets)
- **Resources** — [Agent personas](/docs/personas),
  [Wrappers, Skills & Connectors](/docs/agent-capabilities),
  [Repositories & Integrations](/docs/repositories)
- **Admin** — [Secrets & Variables](/docs/secrets),
  [Team & access](/docs/people-and-access),
  [Analytics](/docs/analytics), [project settings](/docs/project-home)
- **Company** — [the workspace above projects](/docs/company-workspace)

> tip New to Flow? Read [Getting started](/docs/getting-started), then
> [Tasks & the board](/docs/tasks), then the
> [worked examples](/docs/examples). Everything else is reference.
