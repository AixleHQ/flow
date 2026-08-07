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
is reached over `streamable-http` at `Settings.mcp.server_url`
(`MCP_SERVER_URL`) and authenticated with a per-session
`X-Session-Key` header. It exposes:

- **Board tools** (`board_*`) — read and mutate the board: get/list/create/
  update/move tasks, comments, assets, tags, and Waits.
- **Progress tools** (`list_sub_steps`, `mark_sub_step`) — auto-injected
  only in workflow-step sessions.
- **Session lifecycle** (`finish_session`, `fail_session`) — how an agent
  signals it is done or has failed.

These are modelled as platform `Tool` records, not user config — see
[Tools](tools.md).

### Custom servers

Add custom MCP servers under **Company → MCP Servers** or **Project →
MCP Servers**. They resolve additively into a session alongside the
internal server (see [resource resolution](tools.md#resource-resolution)).

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

## Aixle as an MCP server (your personal token)

The same `/mcp` endpoint also serves a **personal** server: not a
session's tools, but your own Aixle account, so an outside client
(Claude Code, Claude Desktop, any MCP client) can drive the platform for
you — list projects, build workflows, run them, work the board.

Enable it under **Profile → Personal MCP**, which hands you an `amcp_`
token and the ready-made command:

```
claude mcp add aixle --transport http $MCP_SERVER_URL --header "Authorization: Bearer amcp_…"
```

The token carries **exactly your own access level** — every call runs
through the same Pundit policies as the UI, across every company you are
an active member of. There is no "current project": tools take an
explicit `project_id`. Regenerating the token revokes the old one.

Beyond its ~85 tools, the server ships its own documentation:

| Surface | Name | What it carries |
| --- | --- | --- |
| `instructions` | — | Returned on `initialize`, so it is in the client's context from the start: the entity model, the rules that prevent damage (read before write, id lists are replaced wholesale, confirm destructive calls), and where the rest lives. |
| prompt | `setup_project` | A project from nothing to a running workflow: company, integrations, repositories, config items, tools/skills/MCP servers, agents, board, workflow, trigger. |
| prompt | `build_workflow` | Workflow concepts and the order to call the workflow tools. |
| prompt | `author_step` | How to write a step an agent can actually run. |
| prompt | `tool_catalog` | Every tool on the server, grouped by area — generated from the live registry, so it cannot drift. |
| resource | `aixle://reference/system` | `references/aixle-system-reference.md`: the full domain model. |

Implementation: `Tools::PersonalMCPRequestHandler` wires the server,
`Tools::PersonalMCPGuides` holds the text, and the tools are the
registry's `audience :user` definitions (`app/services/personal_tools/`).

## See also

- [Tools](tools.md) — what the tools themselves are and how they execute.
- [Integrations](integrations.md) — Git hosts, OAuth sign-in, webhooks.
- [Runtimes](runtimes.md) — which runtimes speak MCP.
