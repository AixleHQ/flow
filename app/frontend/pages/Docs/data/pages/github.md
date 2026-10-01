# Connecting GitHub

GitHub connects per Flow project. Once it is connected, you attach the
repositories it reaches on the project's **Repositories** page, and from then on:

- every session those repositories are attached to gets a checkout of each, with
  every branch and the full commit history;
- `git fetch`, `git push` and `gh` work inside the session with a short-lived
  credential fetched on every call — nothing is stored in the container;
- a workflow step can park a board task until a pull request's checks or a GitHub
  Actions run finish (a CI gate).

Any member who can change the project connects it; viewers cannot.

There are two ways to connect, and they differ in **who Flow acts as** on GitHub.

| | GitHub App | Personal access token |
| --- | --- | --- |
| Who connects | Someone who can install an app on the GitHub account or organization | Anyone with a GitHub token |
| Flow acts as | The app's installation | The token's owner |
| What a session is handed | A short-lived token narrowed to the one repository, fetched on every call | The token itself, with everything it reaches |
| CI gates close | As soon as GitHub reports, through the app's webhooks | On the next polling sweep — a token gets no webhooks |
| Needs on the deployment | The deployment's GitHub App | Nothing |

Use the app in production. The token is for trying Flow out locally or on a
personal project, where nobody can install an app and github.com cannot reach
the deployment.

---

## With the GitHub App

1. On the project's **Integrations** page choose **Connect → GitHub**, keep
   **I own the organization and can install the app (Recommended)**, and select
   **Continue to GitHub**.
2. On GitHub, pick the account or organization and the repositories the app may
   reach, and install it.
3. GitHub sends you back to the project's **Integrations** page with
   *GitHub connected*. The connection is named after the GitHub account.

Finish within ten minutes, signed in as the same Flow user and with the same
company selected. The link Flow hands to GitHub expires after ten minutes and
works only once.

The repositories you grant on GitHub are the ones Flow can list and clone. To
change them later, change the installation's repository access on GitHub — the
row's **Settings** icon links to the installation — and Flow's next listing
follows.

If the app option is greyed out with *Unavailable on this deployment*, the
deployment has no GitHub App; see
[Self-hosted: the GitHub App](#self-hosted-the-github-app).

## With a personal access token

1. Create a token on GitHub. The dialog's **Create a token on GitHub** link opens
   the classic-token form with `repo` already ticked.
2. On the project's **Integrations** page choose **Connect → GitHub**, pick
   **I'm a developer and just want to try it (personal access token)**, paste the
   token into **Personal access token**, and select **Connect**.
3. Flow checks the token with GitHub before saving anything and reports
   *GitHub connected as*, followed by your GitHub login. The row reads
   *token · as*, followed by your Flow name and a classic token's scopes.

### Scopes

A token reaches exactly what it was granted, so a missing scope makes that one
thing fail, not the connection.

- **Classic token:** `repo` covers everything on private repositories;
  `public_repo` covers the same on public ones only. A token with neither is
  refused when you connect, rather than failing later at clone time. Add
  `workflow` if agents will change files under `.github/workflows` — GitHub
  rejects that push without it.
- **Fine-grained token,** on the repositories you will attach:

  | To do this | Grant |
  | --- | --- |
  | Clone and fetch | **Metadata** read, **Contents** read |
  | Push | **Contents** write |
  | Change `.github/workflows` | **Workflows** write |
  | Open and answer pull requests | **Pull requests** write |
  | CI gates | **Checks** read, **Actions** read |

  GitHub does not report a fine-grained token's permissions, so Flow accepts one
  as long as GitHub accepts it, and the row shows no scopes.

### What the token path does not do

- **It acts as you.** Every clone, push and pull request carries your own GitHub
  permissions and is attributed to you, and the connection stops working when
  your access does.
- **It cannot be narrowed.** Every session and tool that works on one of these
  repositories is handed the token itself. Prefer a fine-grained token limited
  to the repositories you connect.
- **No webhooks.** GitHub delivers webhooks to an app, not to a token. CI gates
  resolve by polling instead — and not at all if the deployment cannot reach
  github.com.
- **Tokens expire.** An expired token shows up as a failed clone or fetch.
  Connect again with a new token: it replaces the stored one on the same
  connection, which keeps its repositories. A new token GitHub refuses changes
  nothing — the old one stays.

The token is stored encrypted and never shown again; changing it means pasting
a new one. A project has at most one token connection, beside any number of app
connections.

---

## Adding repositories

Anyone who can edit the project adds them. On **Repositories**, select
**Add Repository**, keep **From integration**, pick the GitHub connection under
**Integration**, then the **Repository** and its **Source branch**. **Purpose** is
optional and tells agents what the repository is for. See
[Repositories](/docs/repositories).

- An app connection lists the repositories the installation was granted. A token
  connection lists the ones the token's owner owns, collaborates on, or reaches
  through an organization. The list stops at 1,000.
- On an app connection, the repository has to belong to the account the app is
  installed on. A repository from another account needs that account's own
  installation.
- Nothing is registered on GitHub per repository; the app's webhooks already
  cover it.

A public repository needs no connection at all: choose **Public repository** and
paste its github.com URL. It is cloned without credentials, so agents can read it
but not push.

Removing a GitHub connection also removes every repository attached through it.
It does not uninstall the app on GitHub; do that on GitHub.

## In a session

Attach repositories to a workflow, a step or a session with its **Repositories**
field. When the session starts, each one is cloned under `/workspace/repo/`:

- The **source branch** is checked out. Every other branch and the full commit
  history are there too (`git branch -r` lists them); file contents of other
  revisions download the first time they are needed.
- No token is written into the checkout, the remote URL or the environment. A
  credential helper asks Flow for a fresh credential on every `git fetch` and
  `git push`, so a long session outlives the hour an installation token lasts.
- `gh` goes through the same helper. Each call gets a credential for one
  repository: the one named with `-R`/`--repo` or `GH_REPO`, the one in a
  `gh api repos/<owner>/<repo>/…` path, else the checkout the call runs in, else
  the session's only GitHub checkout. Agents are told not to run `gh auth login`
  or export a token. If `GH_TOKEN` or `GITHUB_TOKEN` is set, the wrapper steps
  aside and `gh` uses that token instead.

The credential allows what the connection allows: the app's permissions narrowed
to that one repository, or everything the personal access token reaches.

There are no server-side GitHub pull-request tools. An agent opens and answers
pull requests itself, with `gh` or the GitHub API — which is why the
**Pull requests** permission matters.

## CI gates

A workflow step makes a board task wait for GitHub CI with `board_create_gate`:

| `gate_type` | Waits for | Also needs |
| --- | --- | --- |
| `github_checks_completed` | Every check suite on the pull request's current head commit | `repo_full_name`, `pr_number` |
| `github_workflow_completed` | One GitHub Actions workflow run | `repo_full_name`, `run_id` |

The repository has to be attached to the task's project. While a gate is
pending, the column's workflow does not start the next run for the task. The
card shows **CI pending**, then **CI passed**, **CI failed** or **CI stale**, and
links to the pull request or the run.

- **With the app,** GitHub's `check_suite` and `workflow_run` webhooks close the
  gate as soon as CI finishes. A finished check suite only makes Flow ask GitHub
  about every suite on the pull request's head, so a quick lint finishing first
  does not pass a gate while the tests are still running.
- **With a token, or when a webhook was lost,** a sweep every five minutes asks
  GitHub instead, starting ten minutes after the gate was created.

One failing suite fails the gate. A suite that sits queued with no runs — opened
by an app that never reports any — is ignored while another suite has runs.

A gate GitHub cannot answer for — the pull request is gone, it has no check
suites, the repository was removed from the project — is marked **CI stale**
with the reason, and so is a gate still waiting after 12 hours. A stale gate
stops holding the card, but never counts as a pass. See
[Triggers and gates](/docs/triggers-and-gates) for the whole lifecycle.

## Starting a workflow from GitHub

The connection's webhooks only close CI gates; no trigger listens to them. To
start a workflow when something happens on GitHub — a pull request opened, a
push to `main` — point a GitHub webhook at an **Incoming webhook** trigger. This
works with either kind of connection, or with none.

1. On the workflow's **Triggers** tab, select **Add a trigger**, choose
   **Incoming webhook**, and set **Verification** to **HMAC SHA-256**. Leave
   **Secret** blank to have one generated. Copy the **Request URL** and the
   **Secret** from the confirmation.
2. On GitHub, add a webhook to the repository or organization: the Request URL
   as the payload URL, content type `application/json`, the secret, and only the
   events you want.

Flow checks GitHub's `X-Hub-Signature-256` signature and drops a delivery it has
already accepted (`X-GitHub-Delivery`). A form-encoded body is not parsed, which
is why the content type matters.

The trigger sees the JSON body, not GitHub's event name. Choose the events on
GitHub, and narrow further under **Only when (optional)** with a field of the
payload — `action` equal to `opened`, or `ref` equal to `refs/heads/main`.
Dot-paths such as `repository.full_name` work. Without a condition, the ping
GitHub sends when the webhook is created starts a run too.

The payload reaches the agent only through a task. Set
**Subject (what the run is about)** to **Create a task** and pick a
**Task column**: the new card's description carries the JSON, and
**Task title template** takes fields from it, such as `{{pull_request.title}}`.
Every step of the workflow needs auto-run, because nobody is there to start one.

## Tools

| Tool | Who has it | What it is for |
| --- | --- | --- |
| `refresh_github_token` | Any session with a GitHub repository attached | Re-applies the credential helper to the session's GitHub checkouts. For a push or fetch that fails with a 403, *Invalid username or password* or *could not read Username*; retry afterwards, no re-clone needed |
| `board_create_gate` | Workflow-step sessions | Creates a CI gate (above) |
| `board_list_gates` | Workflow-step sessions | What a task is waiting on, its CI verdict so far and, for a stale gate, why |

`refresh_github_token` is not in the tool picker; Flow adds it to every session
that holds a GitHub checkout. The two board tools come with every workflow-step
session. From your own MCP client, the Flow server's `list_integrations` shows a project's connections
and `get_integration_setup_url` returns the page to connect from — credentials
never travel over MCP.

---

## Self-hosted: the GitHub App

Without an app, a deployment offers only the token path. To offer the app path,
the operator registers one GitHub App for the whole deployment:

1. **Setup URL:** `https://<your domain>/company/integrations/github_setup`.
   Every installation returns there, whichever project started it; the project
   travels in a signed `state`.
2. **Webhook:** active, URL `https://<your domain>/webhooks/github`, with a
   secret.
3. **Repository permissions:** Contents read & write, Pull requests read & write,
   Checks read, Actions read, Metadata read. Add Workflows read & write if agents
   will change files under `.github/workflows`.
4. **Events:** Check suite and Workflow run — the two CI gates resolve on. Flow
   ignores every other event.
5. If organizations other than the app's owner will install it, make it
   installable on any account.
6. Generate a private key, and configure Flow:

   ```bash
   GITHUB_APP_ID=<App ID>
   GITHUB_APP_SLUG=<slug, as in github.com/apps/<slug>>
   GITHUB_APP_PRIVATE_KEY="<the PEM>"
   GITHUB_WEBHOOK_SECRET=<the webhook secret>
   ```

The connect dialog offers the app once `GITHUB_APP_ID` and `GITHUB_APP_SLUG` are
set. The key is read when a connection is verified, so a missing or bad key shows
up as a connection in error, not at boot.

- `GITHUB_APP_PRIVATE_KEY` takes the PEM with real newlines, with `\n` escapes,
  or on one line. For a key mounted as a file, set `GITHUB_APP_PRIVATE_KEY_PATH`
  instead; it is read only when the inline key is blank.
- Without `GITHUB_WEBHOOK_SECRET`, every delivery to `/webhooks/github` is refused
  with 401, and CI gates wait for the sweep.
- `GIT_CREDENTIALS_URL` is where the in-container helper asks for credentials.
  It defaults to the internal `/agents/git/credentials` endpoint and must never
  be a public host: each request carries a per-session key.
- `GITHUB_PUBLIC_READ_TOKEN` is unrelated to the app. It only raises the
  api.github.com rate limit for reading public repositories nobody installed the
  app on. It needs no scopes; never use a customer's token for it.

The full list is in [Configuration](/docs/configuration).

### Who may connect an installation

Every customer installs the same app, and the app's key can read every
installation, so an installation's existence proves nothing about who installed
it. By default an installation belongs to one company: the first that connects
it.

To check the person instead, set `GITHUB_APP_CLIENT_ID` and
`GITHUB_APP_CLIENT_SECRET` from the app, turn on
**Request user authorization (OAuth) during installation**, and point the app's
callback URL at the same `/company/integrations/github_setup`. A new
installation then connects only for a GitHub user who can see it, and one
organization can be connected from several companies.

Set the client credentials and the user authorization together. With the
credentials set and the authorization off, GitHub sends no code back, and every
new installation is refused.

## Limits

- **github.com only.** Clones and API calls go to github.com; GitHub Enterprise
  Server is not supported.
- **No connection test.** A GitHub row has no **Test connection**, and its status
  does not follow GitHub: an app uninstalled there still reads active in Flow,
  while its clones fail and its gates wait until they go stale.
- **No GitHub event triggers, and GitHub Issues is not a tracker.** Use an
  Incoming webhook trigger (above); trackers are Jira and Azure Boards — see
  [Trackers](/docs/trackers).
- **The repository picker lists at most 1,000 repositories.**

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| *"You are not authorized to perform this action."* | You are a viewer in this company, and viewers cannot connect | Ask a company admin to change your role, or someone who can change the project |
| *"GitHub App is not configured"*, or the app option is greyed out | The deployment has no `GITHUB_APP_SLUG` or `GITHUB_APP_ID` | Use a token, or have the operator register the app |
| *"Connect a GitHub integration from within a project."* | The return from GitHub carried no valid link: more than ten minutes passed, the install was started on GitHub rather than from Flow, or another company is selected | Start again from the project's **Integrations** page |
| *"GitHub setup link expired or already used — start the connection again."* | The return link was used before, or by a different Flow user | Start again |
| Back on **Integrations**, nothing connected, no message | GitHub returned without an installation — for example, you requested the app from an organization owner instead of installing it | Connect again once it is installed |
| *"This GitHub installation is already connected to another workspace"* | Another company holds this installation | The operator can enable user authorization ([above](#who-may-connect-an-installation)) |
| *"Could not confirm you have access to this GitHub installation"* | The GitHub user who finished the install cannot see it, or the app's user authorization is off while its client credentials are set | Install as someone who can see it; operator: turn the authorization on |
| A row in error, named *GitHub (unverified)* if it never verified, with *"Failed to verify installation: …"*, *"GitHub App ID not configured"*, *"GitHub App private key not configured …"*, *"GitHub App private key file not found at …"* or *"Invalid PEM format"* | The deployment's app configuration | Fix it and connect the same installation again; the row is reused |
| *"GitHub rejected this token — it is invalid, revoked or expired."* | Exactly that | A new token |
| *"This token has no repository access. …"* | A classic token without `repo` or `public_repo` | Add the scope, or use a new token |
| *"… must belong to the `account` GitHub installation"* when adding a repository | The repository's owner is not the account the app is installed on | Install the app on that account too |
| A repository is missing from **Add Repository** | The installation was not granted it, or the token cannot see it | Grant it on GitHub, or widen the token |
| A repository is missing from the agent's list of repositories | Its clone failed: the connection is not active, the source branch is gone, or GitHub refused the credential | Check the connection and the repository's source branch, then start a new session |
| `git push` or `git fetch` fails with a 403, *Invalid username or password* or *could not read Username* | A checkout without the credential helper | The agent runs `refresh_github_token`, then retries |
| A push changing `.github/workflows` is rejected | No `workflow` scope, or no Workflows permission on the app | Add it |
| *"gh: no platform credential for this call — run it inside a checkout under /workspace/repo, or pass -R `owner/repo` …"* | `gh` could not tell which attached repository the call is for | Run it inside the checkout, or pass `-R` |
| *"gh: the platform returned no credential for … — the session may have ended or lost access"* | The session ended, or the repository's connection is no longer active | Check the connection |
| *"Repository … is not linked to this task's project"* from `board_create_gate` | The gate names a repository the project has not attached | Attach it, or fix `repo_full_name` |
| CI gates close only ten minutes or more after CI finishes | No webhook reached Flow: a token connection, a missing `GITHUB_WEBHOOK_SECRET`, or a deployment github.com cannot reach | Use the app, and check the webhook secret and URL |
| **CI stale** with *"… cannot be read: …"* | The pull request, run or repository can no longer be read | Read the reason on the card, then re-run what is needed |
