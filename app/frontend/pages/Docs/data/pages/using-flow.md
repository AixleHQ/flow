# What Flow Is

Aixle Flow is the team layer on top of personal AI coding agents. One person
puts work on a board. An agent picks it up, does the work, and the whole team
sees the run, the output, and the cost — without anyone opening a terminal.

If you are installing or operating Flow, read the [User Guide](/docs/user-guide)
instead. This section is for people who *use* the product.

## The loop

```
Board ── card enters a bound column ──► Workflow ── step by step ──► Agent
  ▲                                                                    │
  └──────────── status, files, comments and cost come back ◄───────────┘
```

1. A card moves into a column that is bound to a workflow.
2. The workflow starts — automatically, or from a button if the column is set
   to manual.
3. Each step of the workflow is one agent session doing one job. Independent
   steps run at the same time.
4. Results come back: files in Assets, comments and status on the card, a full
   trail in Sessions & Runs, and cost in Analytics.

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
- Grok

An agent runs under a credential *a person connected*, which is why
[getting started](/docs/getting-started) begins with connecting one. A persona
you define (see [Agent personas](/docs/personas)) is not tied to a product —
the same persona can run on any of the five.

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
