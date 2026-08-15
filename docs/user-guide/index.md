# User Guide

Aixle Flow turns AI coding agents into a team workflow. The pieces fit
together like this:

```
Board ── card moves to column ──► Workflow ── DAG of Steps ──► Agent in container
  ▲                                                                  │
  └─────────────── results, status, cost return ◄────────────────────┘
```

Read in any order:

- **[Board](board.md)** — projects, columns, cards, and column → workflow bindings.
- **[Workflows](workflows.md)** — DAG steps, retries, approval gates, parallel runs.
- **[Agents](agents.md)** — personas, the container, and how session context is built.
- **[Runtimes](runtimes.md)** — the five LLM CLIs (Claude Code, Cursor CLI,
  Codex, Gemini, Grok), their images, credentials, and cost tracking.
- **[Tools](tools.md)** — tool kinds, execution modes, the built-in board
  tools, and resource resolution.
- **[MCP servers](mcp.md)** — transports, the internal `aixle-tools` server,
  Config Items credentials, and the personal token that turns Aixle itself
  into an MCP server.
- **[Integrations](integrations.md)** — GitHub, GitLab, Linear,
  Google OAuth, and webhooks.
- **[Configuration](configuration.md)** — env vars, OAuth, agent
  credentials, and other knobs.

If you've just installed Aixle Flow and want to see something move, go
to [Quickstart](../quickstart.md) first.

## Mental model in one paragraph

A **Company** owns shared resources. Inside it, **Projects** each have
one **Board**. A Board has ordered **Columns**; each column can be
**bound to a Workflow**. Drop a card into the column and the workflow
starts. A Workflow is a DAG of **Steps**; each Step is one **Agent**
session running in an isolated **container**, producing artifacts and
optionally pushing PRs. Steps can depend on each other (parallel
branches are fine), retry on failure, or block on a human approval.
Every run is tracked with cost, tokens, and a full log.

That's the whole product.
