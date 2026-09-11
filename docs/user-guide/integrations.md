# Integrations

Aixle Flow integrates with Git hosts (for repo mounting and CI waits),
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

### Azure DevOps

Azure DevOps is **project-scoped**: one connection names one Azure
organization and one Azure project inside it. Agents clone, push, open
and review pull requests, and read and update Azure Boards work items.

Unlike GitHub and GitLab, a project owner cannot connect it alone —
access is approved per organization first, because knowing a tenant id
or an organization URL is not proof that your company owns that
organization. Setup runs in three places:

1. **Your Entra administrator** provisions a service principal for
   Aixle's application in your tenant, using the client id your Aixle
   operator publishes. No new app registration is needed, and Aixle's
   private key is never shared.
2. **An Azure DevOps administrator** adds that service principal to the
   organization under **Organization settings → Users**, with at least a
   **Basic** access level (Stakeholder cannot read repositories) and the
   project permissions the agents need. Grant repository Read and
   Contribute, pull-request Contribute, and Boards access to the area
   paths in scope — never project-collection administration or policy
   bypass.
3. **Your Aixle operator** records the approval and the list of Azure
   projects it covers (`rake azure_devops:approve` / `:verify` /
   `:scope`).

Then, in **Project → Integrations → Connect → Azure DevOps**, pick the
approved organization and one of its approved projects, and choose what
agents may do. The selected Azure project is fixed for the life of the
connection: changing it would silently re-point existing repository and
work-item references, so connect again instead.

Operations run as the **application's identity**, not as the person who
connected it — pull requests and comments are authored by it, and an
employee leaving does not revoke it. Repositories authenticate through a
credential helper that fetches a short-lived token per git operation, so
nothing is stored in the checkout; ordinary `git fetch` and `git push`
work with no extra step.

Notes and limits:

- **Azure DevOps Services on `dev.azure.com` with Git repositories
  only.** Azure DevOps Server (on-premises), TFVC, Artifacts, Test Plans
  and Wiki management are out of scope.
- An organization backed by a personal Microsoft account, with no
  connected Entra tenant, cannot use a service principal at all. Those
  organizations need the optional personal-access-token mode, which
  acts as the token's owner and carries that person's permissions.
- Completing or merging a pull request, reviewers and votes, Azure
  Pipelines and Service Hooks are a later parity extension.
- `AZURE_DEVOPS_ENABLED` gates the whole feature per deployment.

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

See the dedicated [MCP servers](mcp.md) page for transports, the
internal server, Config Items credentials, and URL-safety rules — and
[Tools](tools.md) for what the tools themselves are.

## Webhooks reference

| Source        | Endpoint                          | Auth                                        |
| ------------- | --------------------------------- | ------------------------------------------- |
| GitHub        | `POST /webhooks/github`           | HMAC signature with `GITHUB_WEBHOOK_SECRET` |
| GitLab        | `POST /webhooks/gitlab`           | Per-repository secret                       |

Both endpoints are public (no session auth) — verification is
signature-based.
