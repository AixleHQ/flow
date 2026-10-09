# User Guide

Aixle Flow turns AI coding agents into a team workflow. Every run, whatever
started it, takes the same path:

```
 card enters a column · schedule · Slack/Teams · webhook · tracker
                               │ event
                               ▼
      trigger, or Run ── gates may hold it ──► workflow run ──► steps (a DAG)
                                                                     │
                                                                     ▼ one per step
  container ◄── session queue ◄── agent session: persona × runtime × credential
      │
      └──► status, files and cost go back to the source — card, tracker issue,
           chat thread — and into Assets, Sessions & Runs and Analytics
```

Read in any order:

- **[Board](board.md)** — projects, columns, cards, and column → workflow bindings.
- **[Workflows](workflows.md)** — DAG steps, retries, approval gates, parallel runs.
- **[Triggers and gates](triggers-and-gates.md)** — every way a run starts, who it runs as, and the CI gates that hold one back.
- **[Prompt guide](prompt-guide.md)** — writing session instructions an agent can run.
- **[Agents](agents.md)** — personas, the container, and how session context is built.
- **[Runtimes](runtimes.md)** — the seven LLM CLIs (Claude Code, Cursor CLI, Codex, Gemini CLI, Antigravity CLI, Grok, Kiro CLI), their images, credentials, and cost tracking.
- **[Tools](tools.md)** — tool kinds, execution modes, the built-in board tools, and resource resolution.
- **[MCP servers](mcp.md)** — transports, the internal `aixle-tools` server, Config Items credentials, and the personal token that turns Aixle itself into an MCP server.
- **[Integrations](integrations.md)** — GitHub, GitLab, Azure DevOps, Jira, Linear, YouTrack, Slack, Microsoft Teams, Coder and the trackers they provide, and webhooks.
- **[Session queues](session-queues.md)** — why a session waits before its container starts, and the limits behind it.
- **[Configuration](configuration.md)** — env vars, OAuth, agent credentials, and other knobs.
- **[Configuring sign-in methods](configuring-sso.md)** — Google, Microsoft Entra and per-company OpenID Connect on your installation.

If you've just installed Aixle Flow and want to see something move, go
to [Quickstart](../quickstart.md) first.

## Mental model

**Three levels.** A **Company** is the workspace: members and their roles, how
people sign in, capacity and billing, the workflow catalog, company-wide
assets, and the chat apps one install serves to every project (Slack,
Microsoft Teams). A **Project** owns everything a run uses — one board, its
workflows and their triggers, agents, tools, skills, MCP servers,
repositories, trackers, secrets — and none of it crosses into another
project. A person's **Profile** holds what is theirs: the agent credentials
they connected, and their usage.

**Triggers start runs.** A workflow declares how it launches. A card entering a
bound column is one way. The others are **Run** on a task or a workflow (or an
agent calling the MCP tools), a cron schedule, a Slack or Teams message, an
inbound webhook, and an event in a connected tracker — Jira, Linear, YouTrack,
Azure Boards or GitHub Projects. A run that does not start from a card is about
no card, an existing one, or a card it creates. **Gates defer runs:** a card waiting on CI — a
GitHub check, a GitLab pipeline, an Azure build or PR policies — does not set
off its column's workflow until the check reports or goes stale.

**A workflow is a DAG of steps.** Each step is one **Agent** session — a
persona on one of the seven runtimes — in its own isolated container.
Sub-steps are a checklist inside that session, not sessions of their own. Steps
run in parallel where nothing connects them, wait for the steps they depend on,
retry or skip on failure, or pause until a person approves them.

**A session runs on a person's credential.** A run belongs to someone. A
card's run belongs to its assignee when they have a connected agent, else to
whoever moved the card or pressed **Run** on it; a workflow started by hand
belongs to whoever pressed **Run**; any other trigger runs as its creator,
because nobody is at the keyboard when it fires. Each step uses that person's
credential for its runtime. Before its container starts, a session can wait in the
**session queue** until the project and the installation have a free slot.

**Results go back where the run came from.** A card shows the run's status,
comments and files. A chat thread gets a status card that follows the run; a
tracker issue gets a comment if the run fails. Deliverables are kept in
Assets; the full log, tokens and cost in Sessions & Runs and Analytics.
