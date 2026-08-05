# Integrations

Aixle Flow integrates with Git hosts (for repo mounting and CI gates),
OAuth providers (for sign-in), and MCP servers (for tools).

## Git hosts

### GitHub

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

### GitLab

GitLab connects through a **personal/project access token**, not an
OAuth app. Add the integration under **Company → Integrations** (or at
the project level) and paste a token with `api` scope.

- `GITLAB_ENDPOINT` — set this only for self-managed GitLab; it defaults
  to `https://gitlab.com/api/v4`.
- Webhook endpoint: `https://<your-host>/webhooks/gitlab`, verified with
  a per-repository secret.

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
| GitHub        | `POST /webhooks/github`           | HMAC signature with `GITHUB_WEBHOOK_SECRET` |
| GitLab        | `POST /webhooks/gitlab`           | Per-repository secret                       |

Both endpoints are public (no session auth) — verification is
signature-based.
