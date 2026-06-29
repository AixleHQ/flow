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

## See also

- [Tools](tools.md) — what the tools themselves are and how they execute.
- [Integrations](integrations.md) — Git hosts, OAuth sign-in, webhooks.
- [Runtimes](runtimes.md) — which runtimes speak MCP.
