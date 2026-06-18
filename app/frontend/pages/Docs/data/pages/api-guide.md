# API reference

Aixle Flow exposes a REST API under `/api/v1`, plus webhook receivers
for Git host events. A live OpenAPI explorer is served from the running
app itself.

## OpenAPI explorer

When the app is running locally, browse to:

```
http://localhost:4000/api-docs
```

This is the auto-generated, always-up-to-date schema for every
endpoint. Use this as the canonical source — the tables below give you
the shape, but the explorer has the full request/response specs and
lets you try calls inline.

> **info** **Auth required in non-dev environments.** The `/api-docs` endpoint is protected by HTTP Basic Auth in non-dev environments. Set `DOCS_LOGIN` and `DOCS_PASSWORD` env vars to configure credentials.

## Authentication

Most endpoints are session-authenticated (cookie). Sign in via the web
UI first, then your browser session is good for the API too.

Two endpoints are explicitly **unauthenticated** and verified via HMAC
signature instead:

| Endpoint                  | Verification                                        |
| ------------------------- | --------------------------------------------------- |
| `POST /webhooks/github`   | HMAC SHA-256 using `GITHUB_WEBHOOK_SECRET`.         |
| `POST /webhooks/gitlab`   | Per-repository token in `X-Gitlab-Token` header.    |

Internal endpoints (`/api/v1/internal/*`) are reserved for agent
containers and use a different token mechanism (`ws_auth`).

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

Company-scoped workflows live at `/api/v1/workflows/...` (same shape,
no `:project_id`).

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
DELETE /api/v1/projects/:project_id/board/tasks/:task_id/waits/:id
GET    /api/v1/projects/:project_id/board/tasks/:task_id/transitions
GET    /api/v1/projects/:project_id/board/tasks/:task_id/activities
GET    /api/v1/projects/:project_id/board/tasks/:task_id/statistics
```

### Assets

```
GET  /api/v1/assets/presign
POST /api/v1/assets/upload

POST   /api/v1/company/assets
DELETE /api/v1/company/assets/:id
GET    /api/v1/company/assets/:id/download

POST   /api/v1/projects/:project_id/assets
DELETE /api/v1/projects/:project_id/assets/:id
GET    /api/v1/projects/:project_id/assets/:id/download
```

## Real-time

| Channel                          | What it streams                                          |
| -------------------------------- | -------------------------------------------------------- |
| ActionCable at `/cable`          | Board updates, workflow run progress, terminal session output. |
| ActionMCP at `/action_mcp`       | Internal Model Context Protocol endpoint for agent containers. |

## Webhooks

| Endpoint                  | Purpose                                                |
| ------------------------- | ------------------------------------------------------ |
| `POST /webhooks/github`   | Push, pull_request, check_run events from GitHub App.  |
| `POST /webhooks/gitlab`   | GitLab project event hooks.                            |

See the Integrations page for how to wire these up.

## Versioning

The API is versioned at the path level (`/api/v1/...`). Breaking
changes within `v1` are avoided. New major versions will be additive
(`v2` mounted alongside `v1`).
