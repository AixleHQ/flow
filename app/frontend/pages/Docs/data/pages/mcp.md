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

You can point your own agent (Claude Code, Codex, Cursor, …) at Aixle directly —
no session, no container. Enable it on **Profile → MCP** to get a personal
token. Clients register the server under the name `flow`, so its tools
appear as `mcp__flow__list_projects` and so on:

```
claude mcp add flow --transport http https://<your-aixle-host>/mcp \
  --header "Authorization: Bearer amcp_…"
```

For Codex, which reads a bearer token only from an environment variable:

```
export FLOW_MCP_TOKEN="amcp_…"
codex mcp add flow --url https://<your-aixle-host>/mcp --bearer-token-env-var FLOW_MCP_TOKEN
```

Keep the `export` in your shell profile — Codex reads the variable every
time it starts the server.

The same tab has an **Add to Cursor** button (a one-click install
deeplink) and a **Copy JSON** action for any other client's `mcp.json`.
All of these carry the token, so they are only offered while it is on screen
— it is stored as a digest and shown exactly once.

This server is **session-less** and grants **exactly your own access
level** — every action runs through the same permission checks as the UI,
so you can only do in a project what you could do by hand. It exposes the
things you do in the app: list your companies and projects, manage board
tasks, columns and gates, build and run workflows (steps, sub-steps,
triggers, runs), manage agents, custom tools, skills, MCP servers, config
items and repositories, and update project settings.

The **Tools** card on the same tab picks which of those the server offers.
Unchecking what you never use keeps its schemas out of the agent's
context, and the `tool_catalog` prompt then describes exactly the
remaining set. Leaving everything checked means "all tools", so ones added
in a later release arrive switched on. This is not a permission boundary —
the token always runs as you.

The server also documents itself, so a client does not have to guess. Its
`instructions` — in your agent's context from the moment it connects —
explain the entity model and the rules that keep it from doing damage.
Four prompts go deeper on demand: `setup_project` (a project from nothing
to a running workflow), `build_workflow`, `author_step`, and
`tool_catalog` (every tool grouped by area, generated from the live
registry). The full platform reference is served as the resource
`aixle://reference/system`.

Starting from an empty project works end to end: a new project has no
board until `setup_board` creates one from a preset (`simple_kanban`,
`dev_team`, `full_sdlc`), and everything else on the board follows from
there.

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

A package launched through `npx`, `uvx` or `pipx run` must name an exact release
(`name@1.2.3` for npm, `name==1.2.3` for PyPI). Without one, every session would
install whatever was published last (`@playwright/mcp` is the exception: every
session runs the version baked into the agent image). A catalog connector whose registry entry says
`latest` is pinned to the release that is current when you install it. To move
to a newer release, edit the server's command, or install the connector again.

## Credentials (Config Items)

Header and env values can hold a secret directly, or reference a **Config
Item** as `config_item:NAME` (e.g. `Bearer config_item:SENTRY_TOKEN`), which
is resolved at session start. Prefer the reference: the secret then lives in
one place, and rotating it needs no edit to the server.

- Values are encrypted at rest. The UI, the admin panel and the MCP tools show
  which keys are set, never their values.
- A referenced Config Item is attached to every session the server is attached
  to. Its value reaches the container only inside that server's config, each
  delivery is recorded in the item's access log, and the value is redacted
  from the session's logs like any other session secret.
- Values belong to the address they were entered for. Changing a server's
  origin (`http`/`sse`) or its command line (`stdio`) clears every stored
  header and env value and disconnects its OAuth connections — enter them
  again in the same save or afterwards. A new path on the same origin, or
  switching between `http` and `sse`, keeps them.

If an agent can't reach a server, the usual cause is a missing Config Item, a
server whose address changed and was never given its credentials back, or the
wrong `transport`.

## OAuth servers

With **Auth type: OAuth 2.1** the platform discovers the server's authorization
server (RFC 9728, then RFC 8414) and registers itself there, or uses a client
an operator registered by hand when the server does not allow that.

- Discovery refuses metadata that does not describe the server it came from: a
  protected resource on another origin or outside the server's path, an issuer
  other than the one the metadata was fetched for, or a consent page on a site
  that is neither the issuer's nor the MCP server's.
- A **shared** credential is one connection the whole project acts as, so
  connecting or reconnecting it needs edit rights on the project's MCP
  servers. A **per-user** credential is each member's own account; any member
  who can use the server can connect it.
- Every credential records who connected it, and is only ever sent to the
  origin it was issued for.

## URL safety

Custom HTTP/SSE servers are validated against SSRF: the URL must be
`http`/`https`, and it cannot point at `localhost`, cloud metadata
endpoints, or private / loopback / link-local addresses (including
hostnames that resolve to them).

## See also

- **Tools** — what the tools themselves are and how they execute.
- **Integrations** — Git hosts, OAuth sign-in, webhooks.
- **Runtimes** — which runtimes speak MCP.
