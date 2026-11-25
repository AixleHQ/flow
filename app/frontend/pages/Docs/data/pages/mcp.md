# MCP servers

The **Model Context Protocol** is how Aixle Flow gives agents tools.
Every agent session connects to one or more MCP servers; the tools they
expose become callable by the runtime.

## Internal vs custom

MCP servers come in two kinds:

| Kind       | Scope            | Example                                          |
| ---------- | ---------------- | ------------------------------------------------ |
| `internal` | none (platform)  | `aixle-tools` — always connected.                |
| `custom`   | Project          | Context7, Tavily, Playwright, any HTTP/stdio MCP. |

### `aixle-tools` (internal, always on)

Every session container is given the internal `aixle-tools` server. It
is reached over `streamable-http` at `Settings.mcp.server_url` (the
`MCP_SERVER_URL` env variable) and authenticated with a per-session
`X-Session-Key` header. It exposes:

- **Board tools** (`board_*`) — read and mutate the board: get/list/create/
  update/move tasks, comments, assets, tags, and gates.
- **Progress tools** (`list_sub_steps`, `mark_sub_step`) — auto-injected
  only in workflow-step sessions.
- **Session lifecycle** (`finish_session`, `fail_session`) — how an agent
  signals it is done or has failed.

These are modelled as platform `Tool` records, not user config — see
[Tools](/docs/tools).

### Custom servers

Add custom MCP servers under **Project → Connectors**, by hand or from the
public connector catalog. They resolve additively into a session alongside
the internal server (see [resource resolution](/docs/tools#resource-resolution)).

## Personal MCP (connect your own agent)

You can point your own agent (Claude, Claude Code, Codex, Cursor, any MCP
client) at Aixle directly — no session, no container. It acts as your own
Aixle account, so the agent can list projects, build workflows, run them and
work the board for you. Clients register the server under the name `flow`,
so its tools appear as `mcp__flow__list_projects` and so on.

There are two ways to connect: sign in (OAuth), or a personal token. Both
start from the server URL on **Profile → MCP**:
`https://<your-aixle-host>/mcp`, or the address an operator sets in
`MCP_PUBLIC_SERVER_URL`.

### Sign in

A client that supports MCP sign-in needs only the server URL. It sends you to
Aixle to allow access — you sign in if needed, and the consent screen names
the app, the companies it will reach and where your browser goes next — and
keeps its own tokens from then on.

- **Claude, Claude Desktop, Cowork:** add the URL as a custom connector
  (**Customize → Connectors → Add custom connector**). On a Team or Enterprise
  plan an owner adds it once for the organization (**Organization settings →
  Connectors**), and each member connects with their own Aixle account.
  Claude's servers must be able to reach your Aixle host.
- **Claude Code:** `claude mcp add flow --transport http https://<your-aixle-host>/mcp`,
  then `/mcp` to sign in.
- ChatGPT, VS Code and other clients that sign in work the same way.

An app reaches the companies whose sign-in policy the browser session you
allowed it from satisfies — connect from a session signed in with your
company's SSO to reach a company that requires it. **Connected apps** on the
same tab lists every app and disconnects each one on its own. How the
authorization server works:
`docs/design/mcp-oauth-server.md`.

### Personal token

For clients that cannot sign in, **Create token** on **Profile → MCP** gives
you an `amcp_` token and, alongside it, the ways to install the server:

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

The same tab has an **Add to Cursor** button — a
`cursor://anysphere.cursor-deeplink/mcp/install` link carrying the URL and
the bearer header — and a **Copy JSON** action for any other client's
`mcp.json`. All of these carry the token, so they are only offered while it
is on screen — it is stored as a digest and shown exactly once.

Regenerating the token revokes the old one at once. **Disable all MCP
access** ends the token and every connected app.

### What the server covers

This server is **session-less** and grants **exactly your own access
level** — every action runs through the same permission checks as the UI,
across every company you are an active member of, so you can only do in a
project what you could do by hand. There is no "current project": tools take
an explicit `project_id`. It exposes the things you do in the app: list your
companies and projects, manage board tasks, columns and gates, build and run
workflows (steps, sub-steps, triggers, runs), manage agents, custom tools,
skills, MCP servers, config items and repositories, and update project
settings.

The server also documents itself, so a client does not have to guess:

| Surface | Name | What it carries |
| --- | --- | --- |
| `instructions` | — | Returned on `initialize`, so it is in the client's context from the start: the entity model, the rules that prevent damage (read before write, id lists are replaced wholesale, confirm destructive calls), and where the rest lives. |
| prompt | `setup_project` | A project from nothing to a running workflow: company, integrations, repositories, config items, tools/skills/MCP servers, agents, board, workflow, trigger. |
| prompt | `build_workflow` | Workflow concepts and the order to call the workflow tools. |
| prompt | `author_step` | How to write a step an agent can actually run. |
| prompt | `publish_template` | How to turn a working project or workflow into a template for the public catalog and open the pull request. |
| prompt | `tool_catalog` | Every tool the server serves, grouped by area — generated from the live registry, so it cannot drift. |
| resource | `aixle://reference/system` | `references/aixle-system-reference.md`: the full platform reference. |

Implementation: `Tools::PersonalMCPRequestHandler` wires the server,
`Tools::PersonalMCPGuides` holds the text, and the tools are the
registry's `audience :user` definitions (`app/services/personal_tools/`).

Starting from an empty project works end to end: a new project has no
board until `setup_board` creates one from a preset (`simple_kanban`,
`dev_team`, `full_sdlc`), and everything else on the board follows from
there.

Files go onto a task without passing through the agent's context:
`create_task_asset_upload` returns an upload URL valid for an hour, the
agent PUTs the file to it (for example `curl -T screenshot.png '<url>'`),
and `attach_task_asset` attaches it, as an upload in the UI would. Short
text — notes, a log, JSON — goes straight into `attach_task_asset`'s
`content`.

A workflow built this way can be wired up end to end: `create_workflow_trigger`
attaches a board column, a Slack or Teams message, a cron schedule, an
inbound webhook, a tracker event or a pull request event, so the workflow
launches on its own rather than only on a button. When a run misbehaves,
`get_step_run` returns that step's error, retry history and
container-session diagnostics — the same detail the run page shows.

`list_sessions` and `list_workflow_runs` filter, sort and page like the
**Sessions & Runs** list. Sessions filter by company, project, status, kind
(agent session or workflow step), agent, owner, workflow, prompt text and
creation dates; runs by workflow, status, who started them, agent, workflow
name and creation dates. Both sort by date, cost, tokens or duration and return
one page at a time (`limit`, `offset`, with `total` and `has_more`). A run's row
carries its tokens and cost, summed over its steps, and the board task it was
started for (`task_number`, `task_title`, as `get_workflow_run` also returns);
`list_sessions` adds
`totals` over every matching session. To find which sessions spent the most
tokens last week, pass `state: "all"`, `created_from` / `created_until` and
`sort: "total_tokens"`.

Teams are covered too: `list_project_teams`, `create_project_team`,
`update_project_team` and `delete_project_team` manage a project's teams;
`create_board_task` and `update_board_task` take `assignee_team_id`, and
`create_workflow_trigger` and `update_workflow_trigger` take `run_as_team_id`,
so a trigger built over MCP can run as a team from the start.

### Choosing which tools it serves

The **Tools** card on **Profile → MCP** lists every tool the server can
offer, grouped the way the `tool_catalog` prompt groups them. Unchecking the
ones you never use keeps their schemas out of your agent's context, and the
`tool_catalog` prompt then describes exactly the remaining set. It is not a
permission boundary — the token and every connected app always run as you,
with your access level — just a smaller surface.

Leaving everything checked is stored as "all tools", so tools added in a
later release arrive switched on. A client picks up a change on its next
connection.

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
  delivery is recorded in the item's access log (`config_item_accesses`,
  channel `mcp_config`), and the value is redacted from the session's logs like
  any other session secret.
- Values belong to the address they were entered for. Changing a server's
  origin (`http`/`sse`) or its command line (`stdio`) clears every stored
  header and env value and disconnects its OAuth connections — enter them
  again in the same save or afterwards. A new path on the same origin, or
  switching between `http` and `sse`, keeps them. An OAuth credential is only
  ever sent to the origin it was issued for.

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

- [Tools](/docs/tools) — what the tools themselves are and how they execute.
- [Integrations](/docs/integrations) — Git hosts, OAuth sign-in, webhooks.
- [Runtimes](/docs/runtimes) — which runtimes speak MCP.
