# MCP servers

The **Model Context Protocol** is how Aixle Flow gives agents tools.
Every agent session connects to one or more MCP servers; the tools they
expose become callable by the runtime.

## Internal vs custom

MCP servers come in two kinds:

| Kind       | Scope            | Example                                          |
| ---------- | ---------------- | ------------------------------------------------ |
| `internal` | none (platform)  | `aixle-tools` — always connected.                |
| `custom`   | Company / Project | Context7, Tavily, Playwright, any HTTP/stdio MCP. |

### `aixle-tools` (internal, always on)

Every session container is given the internal `aixle-tools` server. It
is reached over `streamable-http` at the `MCP_SERVER_URL` env variable
and authenticated with a per-session `X-Session-Key` header. It exposes:

- **Board tools** (`board_*`) — read and mutate the board: get/list/create/
  update/move tasks, comments, assets, tags, and Gates.
- **Progress tools** (`list_sub_steps`, `mark_sub_step`) — auto-injected
  only in workflow-step sessions.
- **Session lifecycle** (`finish_session`, `fail_session`) — how an agent
  signals it is done or has failed.

These are modelled as platform `Tool` records, not user config — see
the Tools page.

### Custom servers

Add custom MCP servers under **Company → MCP Servers** or **Project →
MCP Servers**. They resolve additively into a session alongside the
internal server (see resource resolution on the Tools page).

## Personal MCP (connect your own agent)

You can point your own agent (Claude Code, Cursor, …) at Aixle directly —
no session, no container. Enable **Personal MCP** on your profile to get a
personal token; the profile page shows the exact command to add it, e.g.:

```
claude mcp add aixle --transport http https://<your-aixle-host>/mcp \
  --header "Authorization: Bearer amcp_…"
```

This server is **session-less** and grants **exactly your own access
level** — every action runs through the same permission checks as the UI,
so you can only do in a project what you could do by hand. It exposes the
things you do in the app: list your companies and projects, manage board
tasks, columns and gates, build and run workflows (steps, sub-steps,
triggers, runs), manage agents, custom tools, skills, MCP servers, config
items and repositories, and update project settings. Two built-in prompts,
`build_workflow` and `author_step`, guide multi-step construction.

A workflow built this way can be wired up end to end: `create_workflow_trigger`
attaches a board column, a Slack message, a cron schedule or an inbound
webhook, so the workflow launches on its own rather than only on a button.
When a run misbehaves, `get_step_run` returns that step's error, retry
history and container-session diagnostics — the same detail the run page
shows.

The token is shown once — regenerate or disable it any time from your
profile. Regenerating immediately invalidates the old token.

## Transports

| Transport | When to use                                                    |
| --------- | -------------------------------------------------------------- |
| `http`    | Server reachable over HTTP. Most managed MCP servers use this. |
| `sse`     | Server-Sent Events — for long-lived tool calls with streaming. |
| `stdio`   | Local subprocess — server is invoked via a `command`.          |

For `stdio`, set `command` (e.g. `npx @playwright/mcp --headless`); the
platform splits it into executable + args. For `http`/`sse`, set `url`.

## Credentials (Config Items)

Custom servers don't store secrets inline. Header and env values can
reference **Config Items**, which are resolved at session start — so the
secret lives in one encrypted place and the server config just points at
it. If an agent can't reach a server, the usual cause is a missing
Config Item or the wrong `transport`.

## URL safety

Custom HTTP/SSE servers are validated against SSRF: the URL must be
`http`/`https`, and it cannot point at `localhost`, cloud metadata
endpoints, or private / loopback / link-local addresses (including
hostnames that resolve to them).

## See also

- **Tools** — what the tools themselves are and how they execute.
- **Integrations** — Git hosts, OAuth sign-in, webhooks.
- **Runtimes** — which runtimes speak MCP.
