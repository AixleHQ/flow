# Integrations

Aixle Flow integrates with Git hosts (for repo mounting and CI gates),
OAuth providers (for sign-in), and MCP servers (for tools).

## Git hosts

### GitHub

GitHub connects two ways, and **Connect → GitHub** asks which before it
does anything:

| Path | Who it is for | What it gives |
| --- | --- | --- |
| **GitHub App** (recommended) | Someone who can install an app on the org or account | Short-lived, repository-scoped installation tokens; org-wide repository access; webhooks that close CI gates the moment a check finishes |
| **Personal access token** | A developer trying Aixle out | A connection with no app to install and no `GITHUB_APP_*` on the deployment. Acts as the token's owner; no webhooks |

#### GitHub App (production)

Aixle Flow installs as a **GitHub App** — this gives it a per-repo
installation token used to clone, push, and watch checks.

1. Go to [github.com/settings/apps](https://github.com/settings/apps)
   and create a new App. Or for the org-level App, go to your org's
   Apps settings.
2. Required permissions: **Repository → Contents (Read & write)**,
   **Pull requests (Read & write)**, **Checks (Read)**, **Metadata
   (Read)**.
3. Subscribe to webhook events: `push`, `pull_request`, `check_run`.
4. Webhook URL: `https://<your-host>/webhooks/github`.
5. Set a webhook secret and copy it to `GITHUB_WEBHOOK_SECRET` in
   `.env.development`.
6. Copy the App ID, slug, and Private Key into `GITHUB_APP_ID`,
   `GITHUB_APP_SLUG`, and `GITHUB_APP_PRIVATE_KEY`.

When users install the App on their repos, Aixle Flow stores the
installation and exposes those repos to projects.

#### Personal access token (local try-out)

A local deployment usually has no GitHub App, nobody with rights to
install one, and no address github.com can call back. Pick **I'm a
developer and just want to try it** in the connect dialog and paste a
token instead; the connection goes active without `GITHUB_APP_ID`, a
private key or an install callback, and you can then attach any
repository the token reaches and clone it in an agent session.

Scopes to give the token:

- **Classic token:** `repo` for private repositories, or `public_repo`
  if you only need public ones. A token with neither is refused at
  connect time rather than failing later at clone time.
- **Fine-grained token:** **Contents** read — and write if agents should
  push — plus **Metadata** read, on the repositories you mean to attach.

What the token path does *not* do, on purpose:

- **It acts as you.** Clones, pushes and pull requests carry the token
  owner's own permissions and authorship, and the token stops working
  when that person's access does. Use the App in production.
- **No GitHub webhooks.** GitHub delivers installation webhooks to an
  App, not to a token, and a local deployment is usually unreachable
  from github.com anyway. CI gates that wait on `push`, `pull_request`
  or `check_run` therefore resolve by polling (the gate reconciler's
  sweep) rather than the moment a check finishes — and not at all if
  this deployment cannot reach api.github.com.
- **Tokens expire.** GitHub expires personal access tokens, and an
  expired one shows up as a 401 on the next clone or fetch. Re-connect
  with a new token; pasting one replaces the stored token on the same
  connection, keeping its attached repositories.

The token is stored encrypted, write-only: it is never rendered back,
and changing it means pasting a new one. An App connection and a token
connection can both exist in the same project, and existing App
connections are untouched by any of this.

### GitLab

GitLab connects through a **personal/project access token**, not an
OAuth app. Add the integration under **Company → Integrations** (or at
the project level) and paste a token with `api` scope.

- `GITLAB_ENDPOINT` — set this only for self-managed GitLab; it defaults
  to `https://gitlab.com/api/v4`.
- Webhook endpoint: `https://<your-host>/webhooks/gitlab`, verified with
  a per-repository secret.

### Azure DevOps

Azure DevOps connects **per project**, not per company: one connection
names one Azure organization and one or more Azure projects inside it.
Agents clone, push, open and review pull requests, and read and write
Azure Boards work items in those projects and nowhere else.

Connecting is self-service — someone who administers the organization
pastes a personal access token once, and the connection runs on Aixle's
own identity afterwards, not on that token. The full walkthrough,
including what differs between the SaaS and self-hosted deployments, is
on the [Azure DevOps](/docs/azure-devops) page.

- Webhook endpoint: `https://<your-host>/webhooks/azure_devops/<endpoint id>`.
  Subscriptions are created automatically and authenticate with a
  per-subscription password — Azure sends no signature of any kind.
- Repositories authenticate through a credential helper that fetches a
  short-lived token per git operation, so nothing is stored in the
  checkout.

### Public repositories (no integration)

A project can also attach any **public** github.com or gitlab.com
repository — nobody has to install the App on it. Under **Project →
Repositories → Add Repository**, switch to **Public repository** and
paste the url.

Aixle Flow verifies the repository exists and is public, then clones it
into sessions **without any credentials**. That means:

- read-only — agents can read the code, but cannot push or open PRs, and
  tools taking a `repository_id` refuse these repositories;
- no CI events — checks and pipeline gates only work for repositories
  reached through an integration;
- optional: set `GITHUB_PUBLIC_READ_TOKEN` (any token, no scopes needed)
  to lift the anonymous api.github.com limit of 60 requests/hour that
  the verification step shares with the skills catalog.

To let an agent write to a public repository, fork it into an
organisation where the App is installed and connect the fork instead.

### Linear

Linear is supported as an issue-tracker integration (connected under
**Company → Integrations**). It is used to pull task context into runs.

## OAuth sign-in

### Google

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/).
2. Enable the **People API** under **APIs & Services → Library**.
3. Create an OAuth 2.0 Client ID. Authorized redirect URI for local dev:
   `http://localhost:4000/auth/google/callback`. Production:
   `https://<your-host>/auth/google/callback`.
4. Put the values into `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

Without Google OAuth configured, the Google login button redirects to
`/auth/failure`. Password-based login still works.

## MCP servers

The **Model Context Protocol** is how external tools reach agents. Add
servers under **Company → MCP Servers** or **Project → MCP Servers**,
over `http`, `sse`, or `stdio`. The platform's own internal
`aixle-tools` server is always connected.

See the MCP servers page for transports, the internal server, Config
Items credentials, and URL-safety rules — and the Tools page for what
the tools themselves are.

## Webhooks reference

| Source        | Endpoint                          | Auth                                        |
| ------------- | --------------------------------- | ------------------------------------------- |
| GitHub        | `POST /webhooks/github`                      | HMAC signature with `GITHUB_WEBHOOK_SECRET` |
| GitLab        | `POST /webhooks/gitlab`                      | Per-repository secret                       |
| Azure DevOps  | `POST /webhooks/azure_devops/<endpoint id>`  | HTTP Basic, one password per subscription   |

All three are public (no session auth). GitHub and GitLab are verified by
signature; Azure DevOps sends none, so the subscription's own password is
the entire credential — which is why the endpoint id in the URL is a
route, never a secret.
