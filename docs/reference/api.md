# API reference

Aixle Flow exposes a REST API under `/api/v1`, an MCP server, and webhook
receivers for Git hosts, Slack, and other sources. A live OpenAPI explorer
is served from the running app itself.

## OpenAPI explorer

When the app is running locally, browse to:

```
http://localhost:4000/api-docs
```

This is the auto-generated, always-up-to-date schema for every
endpoint. Use this as the canonical source — the tables below give you
the shape, but the explorer has the full request/response specs and
lets you try calls inline.

> The `/api-docs` endpoint is protected by HTTP Basic Auth in non-dev
> environments. Set `DOCS_LOGIN` and `DOCS_PASSWORD` env vars to
> configure credentials; with either unset it admits nobody.

## Authentication

The `/api/v1` endpoints are the API the web app itself calls. They are
authenticated by the signed-in browser session (the `_aixle_session`
cookie): sign in via the web UI first, then your browser session is good
for the API too. Requests other than GET must also send the page's CSRF
token in `X-CSRF-Token`. There is no API token or login endpoint here —
programmatic access goes through the MCP server with a personal token.

The endpoints that answer without a browser session authenticate their
caller themselves:

| Endpoint | Caller | Authenticated by |
| -------- | ------ | ---------------- |
| `POST /webhooks/github` | GitHub App | HMAC SHA-256 signature using `GITHUB_WEBHOOK_SECRET`. |
| `POST /webhooks/gitlab` | GitLab project hook | The repository's secret in the `X-Gitlab-Token` header. |
| `POST /webhooks/azure_devops/:endpoint_id` | Azure DevOps Service Hooks | HTTP Basic, with the credentials of that subscription. |
| `POST /webhooks/slack/events` | Slack Events API | The Slack app's signing secret. |
| `POST /webhooks/in/:slug` | Any configured source | The endpoint's own verification strategy, checked on the raw body. |
| `GET /api/v1/internal/ws_auth` | Traefik ForwardAuth, before it proxies a container's terminal, IDE, or file view | A signed-in viewer: the session cookie on the app's host, or a short-lived container ticket on a sandbox host. The viewer must be allowed to reach the session, only the session's owner gets the writable terminal and the IDE, and the session must be `ready`. |
| `POST /api/v1/internal/usage_statistics` | The OTLP ingest relay, forwarding agent telemetry | Each batch names its session in the `terminal_session_token` resource attribute and proves it with `terminal_session_key`, a key the app derives from that session and recomputes on arrival. |
| `/mcp`, `/action_mcp` | Agent sessions; people's own agents | A session's MCP key, or a personal MCP token (`amcp_…`), in `X-Session-Key` or `Authorization: Bearer`. |
| `POST /cloud/aws/credentials`, `/agents/credentials`, `/agents/git/credentials`, `/azure/git/credentials` | Helpers inside an agent container | `X-Session-Id` plus a key the app derives for that session; a session that is no longer active is refused. |

## REST surface — by resource

### Workflows

```
GET    /api/v1/projects/:project_id/workflows/:id
PATCH  /api/v1/projects/:project_id/workflows/:id
DELETE /api/v1/projects/:project_id/workflows/:id

GET    /api/v1/projects/:project_id/workflows/:wf_id/steps
POST   /api/v1/projects/:project_id/workflows/:wf_id/steps
PATCH  /api/v1/projects/:project_id/workflows/:wf_id/steps/reorder
GET    /api/v1/projects/:project_id/workflows/:wf_id/steps/:id
PATCH  /api/v1/projects/:project_id/workflows/:wf_id/steps/:id
DELETE /api/v1/projects/:project_id/workflows/:wf_id/steps/:id
```

Triggers hang off the same path: `GET`/`POST
/api/v1/projects/:project_id/workflows/:wf_id/triggers` and
`PATCH`/`DELETE .../triggers/:id`.

### Workflow runs

Run lifecycle actions live in the **web** namespace (they back the
Inertia-rendered UI). They're documented here because they're stable
and you can call them from a session-authenticated client:

```
POST /company/projects/:project_id/workflow_runs                  (start a run)
POST /company/projects/:project_id/workflow_runs/:id/cancel
POST /company/projects/:project_id/workflow_runs/:id/approve_step
POST /company/projects/:project_id/workflow_runs/:id/retry_step
POST /company/projects/:project_id/workflow_runs/:id/skip_step
```

Asset endpoints for a workflow run are in `/api/v1`:

```
GET  /api/v1/projects/:project_id/workflow_runs/:run_id/workflow_run_assets
POST /api/v1/projects/:project_id/workflow_runs/:run_id/workflow_run_assets/export_all
POST /api/v1/projects/:project_id/workflow_runs/:run_id/workflow_run_assets/:id/export
GET  /api/v1/projects/:project_id/workflow_runs/:run_id/workflow_run_assets/:id/download
```

### Terminal sessions

```
GET    /api/v1/terminal_sessions/:id
POST   /api/v1/terminal_sessions
DELETE /api/v1/terminal_sessions/:id
POST   /api/v1/terminal_sessions/:id/finish
```

### Board

```
POST   /api/v1/projects/:project_id/board
PATCH  /api/v1/projects/:project_id/board
DELETE /api/v1/projects/:project_id/board

GET    /api/v1/projects/:project_id/board/columns
POST   /api/v1/projects/:project_id/board/columns
PATCH  /api/v1/projects/:project_id/board/columns/reorder
GET    /api/v1/projects/:project_id/board/columns/:id
PATCH  /api/v1/projects/:project_id/board/columns/:id
DELETE /api/v1/projects/:project_id/board/columns/:id

GET    /api/v1/projects/:project_id/board/columns/:column_id/workflow_binding
POST   /api/v1/projects/:project_id/board/columns/:column_id/workflow_binding
PATCH  /api/v1/projects/:project_id/board/columns/:column_id/workflow_binding
DELETE /api/v1/projects/:project_id/board/columns/:column_id/workflow_binding

GET    /api/v1/projects/:project_id/board/activities

GET    /api/v1/projects/:project_id/board/tasks
POST   /api/v1/projects/:project_id/board/tasks
GET    /api/v1/projects/:project_id/board/tasks/:id
PATCH  /api/v1/projects/:project_id/board/tasks/:id
DELETE /api/v1/projects/:project_id/board/tasks/:id
PATCH  /api/v1/projects/:project_id/board/tasks/:id/move
POST   /api/v1/projects/:project_id/board/tasks/:id/trigger_workflow
GET    /api/v1/projects/:project_id/board/tasks/:id/workflow_runs

GET    /api/v1/projects/:project_id/board/tasks/:task_id/comments
POST   /api/v1/projects/:project_id/board/tasks/:task_id/comments
GET    /api/v1/projects/:project_id/board/tasks/:task_id/assets
POST   /api/v1/projects/:project_id/board/tasks/:task_id/assets
DELETE /api/v1/projects/:project_id/board/tasks/:task_id/assets/:id
DELETE /api/v1/projects/:project_id/board/tasks/:task_id/gates/:id
GET    /api/v1/projects/:project_id/board/tasks/:task_id/transitions
GET    /api/v1/projects/:project_id/board/tasks/:task_id/activities
GET    /api/v1/projects/:project_id/board/tasks/:task_id/statistics
```

`GET .../board/tasks` is the board's pagination endpoint — the board page
props carry only the first page of each column, and the column pulls the
rest from here as it is scrolled:

| Query param                            | Meaning                                                             |
| -------------------------------------- | ------------------------------------------------------------------- |
| `board_column_id`                      | Restrict to one column.                                             |
| `limit` / `offset`                     | Page window, ordered by `position` then `id`.                       |
| `q[title_cont]`, `q[assignee_id_eq]`, … | Ransack predicates over `BoardTask.ransackable_attributes`.         |
| `tags[]` + `tags_match=all`            | Tag filter. Default matches any listed tag; `all` requires them all. |
| `archived`                             | `archived` for archived only, `all` for both; default active only.   |

The response carries the **unpaginated** match count in the
`X-Total-Count` header, which is how a column header shows its real total
while holding a single page.

### Assets

```
GET /api/v1/assets/presign          # -> { method: "PUT", url, key } for a direct upload
PUT /api/v1/assets/upload/*key      # development/test only: stands in for S3

POST   /api/v1/company/assets
DELETE /api/v1/company/assets/:id
GET    /api/v1/company/assets/:id/download

POST   /api/v1/projects/:project_id/assets
DELETE /api/v1/projects/:project_id/assets/:id
GET    /api/v1/projects/:project_id/assets/:id/download
```

## Real-time

| Endpoint                 | What it carries                                                   |
| ------------------------ | ----------------------------------------------------------------- |
| Action Cable at `/cable` | Inertia Cable signed streams: refresh signals for boards, runs, and sessions, and id-only row updates for the session and run lists. Never record data — the page fetches what changed through its own authorized request. |
| `/t/:route_token/...`    | A session's terminal, IDE, and file views, proxied by Traefik to the container once `ws_auth` admits the viewer. |

## MCP server

`/mcp` and `/action_mcp` (the path agent containers are configured with,
`MCP_SERVER_URL`) serve the same Model Context Protocol endpoint. An agent
session reaches it with its session key and gets the session's tools; a
person reaches it with a personal MCP token and gets the tools of their own
account.

## Webhooks

| Endpoint                                   | Purpose                                                        |
| ------------------------------------------ | -------------------------------------------------------------- |
| `POST /webhooks/github`                    | `check_suite` and `workflow_run` events from the GitHub App.   |
| `POST /webhooks/gitlab`                    | GitLab pipeline hooks.                                         |
| `POST /webhooks/azure_devops/:endpoint_id` | Azure DevOps Service Hook deliveries.                          |
| `POST /webhooks/slack/events`              | Slack Events API, routed to the workspace's installation.      |
| `POST /webhooks/in/:slug`                  | Generic inbound webhooks that fire workflow triggers.          |

See [user-guide/integrations.md](../user-guide/integrations.md) for
how to wire these up.

## Versioning

The API is versioned at the path level (`/api/v1/...`). Breaking
changes within `v1` are avoided. New major versions will be additive
(`v2` mounted alongside `v1`). See [ROADMAP.md](../../ROADMAP.md) for
API stability status.
