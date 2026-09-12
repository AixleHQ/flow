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

Connecting is self-service, with one step outside Flow:

1. **Once per directory,** an Entra administrator instantiates Aixle's
   application in your tenant: `az ad sp create --id <client id>`, with
   the client id your Aixle operator publishes. Nothing is consented to
   and no permission is granted — it only makes the application nameable
   in your organization. Aixle's private key is never shared, and you do
   not register an application of your own.
2. **In Flow,** open **Project → Integrations → Connect → Azure DevOps**,
   type your organization name, and paste a personal access token from
   someone who can administer it (scope: **Member Entitlement Management
   (read & write)**).

That token is used once, in that request: it proves the organization is
yours, and it adds Aixle to it with a **Basic** access level and
Contributor rights on the project you pick. It is never stored, and the
connection runs on Aixle's own identity afterwards — not on your token.
Colleagues connecting further projects in the same organization are not
asked for one, because the first connection already established it.

The selected Azure project is fixed for the life of the connection:
changing it would silently re-point existing repository and work-item
references, so connect again instead.

Operations run as the **application's identity**, not as the person who
connected it — pull requests and comments are authored by it, and an
employee leaving does not revoke it. Repositories authenticate through a
credential helper that fetches a short-lived token per git operation, so
nothing is stored in the checkout; ordinary `git fetch` and `git push`
work with no extra step.

**The Azure tools are not something you attach.** There is no Azure group
in the tool picker: an agent gets the work-item and build tools as soon
as the project has a connection, and the pull-request tools as soon as
the session has an Azure repository attached. Attaching the repository is
the opt-in. This is deliberate — a picker would let someone attach half a
set, so an agent could open a pull request and then be unable to answer
the review it started.

What an agent may *do* with them is still yours to set: the capability
checkboxes on the connection decide which calls are sent at all, and
completing pull requests stays off unless you tick it.

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
- The connect entry appears only once an operator has configured the
  deployment's Entra application (`AZURE_DEVOPS_CLIENT_ID` plus a
  certificate or secret), or switched on personal-access-token mode.
  There is no separate enable flag.

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
