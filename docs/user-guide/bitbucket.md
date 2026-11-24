# Connecting Bitbucket

Bitbucket Cloud connects per Flow project, in one of two ways:

- **The Aixle Flow app** (recommended). A workspace admin installs the app on
  the Bitbucket workspace and connects it to the Flow company once. Flow then
  acts as the app's own bot user, with short-lived tokens Bitbucket hands it,
  and Bitbucket tells Flow when CI finishes.
- **A token.** Someone pastes a workspace, project or repository **access
  token**, or a personal **API token**, into the connect dialog. Flow acts as
  that token's bot or user. Use it when the deployment has no app registered,
  or to try Flow quickly.

Either way, from then on:

- you attach the workspace's repositories as **repositories**;
- agents clone, fetch and push them in their sessions, without a token ever
  sitting in the checkout;
- agents open, review, comment on and merge pull requests with the
  `pull_request_*` tools;
- a CI gate on a board task waits for the pull request's builds.

Bitbucket Data Center is not supported. Bitbucket issues are not a tracker —
connect Jira for that ([Jira](/docs/jira)).

## Who does what

- A **workspace admin** in Bitbucket installs the app and confirms the
  connection from the workspace's settings.
- A member who can change the Flow project connects Bitbucket there and adds
  repositories; viewers cannot.
- The operator registers the app for the deployment once and sets the
  `BITBUCKET_FORGE_*` variables ([Configuration](/docs/configuration); the
  procedure is `docs/operations/bitbucket-app.md` in the repository). Without
  them, the connect dialog offers only the token path.

---

## Connect with the app

1. On the project's **Integrations** page choose **Connect → Atlassian →
   Bitbucket**, keep **Install the app**, and type the workspace (the part
   after `bitbucket.org/`).
2. If the company has already connected that workspace, the project is
   connected and you are done. Otherwise Flow shows **Install the app**.
3. A workspace admin opens it, picks the workspace and approves what the app
   asks for: reading the workspace and its projects, reading and writing its
   repositories and pull requests, and reading its pipelines. The app appears
   in the workspace within a few minutes.
4. In Bitbucket, the admin opens **Workspace settings → Aixle Flow** and selects
   **Connect**. Flow opens in a new tab.
5. Sign in if Flow asks — it brings you back to this page. Flow shows the
   workspace; pick the project to connect it to and select **Connect**.

The workspace is now connected to the Flow company. Further projects in that
company connect by typing the workspace on their own **Integrations** page —
no trip to Bitbucket. One workspace belongs to one Flow company at a time.

**Workspace settings → Aixle Flow** keeps showing which Flow company and
projects the workspace is connected to, and by whom. **Disconnect** there
unbinds it: every Flow project using it stops reaching the workspace until it
is connected again. The connect link Flow hands out works once, for ten
minutes; never send it to anyone.

When the app needs new permissions, Bitbucket asks a workspace admin to
approve its update. Until someone does, the app keeps working as it did.

### What the app can reach

The app is installed on the whole workspace. It reaches every repository its
bot user may read in that workspace, and the token a session uses can reach
all of them for as long as it lives (up to four hours). That is the same as a
GitLab personal access token today, and unlike GitHub, where each session's
token is narrowed to one repository. If a project must reach only some
repositories, connect it with repository access tokens instead.

Branch restrictions apply to the app's bot like to anyone else: a branch that
only some users may push to refuses the app until it is allowed there.

### When the app goes quiet

Bitbucket hands Flow a fresh token every five minutes and with every event;
Flow cannot ask for one. A token lives at least two hours, so a Flow outage
shorter than that goes unnoticed. If the app stops reporting, the integration
row says how long ago it was last heard from, and new clones fail with that
message until it reports again. Removing the app from the workspace puts every
connection that used it into **Error**.

## Connect with a token

1. In Bitbucket, create one of:
   - a **workspace access token** (Premium plan) or **project access token**
     (Premium) — a bot that reaches every repository in the workspace or
     project;
   - a **repository access token** — a bot for one repository;
   - an **API token** with scopes, under your Atlassian account — it acts as
     you and expires within a year.
2. Give it these scopes: repository **read** and **write**, pull requests
   **read** and **write**, pipelines **read**. An API token also needs account
   **read** and workspace **read**. Repository write does not include read in
   Bitbucket; select both.
3. On **Integrations** choose **Connect → Atlassian → Bitbucket → Use a token**,
   type the workspace, paste the token and select **Connect**.

Flow works out which kind of token it is and checks it before saving anything.
An API token's connection is named after its owner; a repository access token's
after its repository (`workspace/repo`); a workspace or project access token's
after the workspace. Connecting again with a token for the same owner — or,
for an access token, reaching the same repository or the same workspace —
replaces the old token and keeps the repositories attached. Repository access
tokens for different repositories are separate connections. **Test
connection** on the row asks Bitbucket about the stored token; **Replace
token** swaps it.

A token connection gets no events from Bitbucket, so its CI gates resolve on
the reconciliation sweep (see [CI gates](#ci-gates)).

## Attaching repositories

On **Repositories → Add Repository**, keep **From integration** and pick the
Bitbucket connection, a repository, the source branch sessions check out, and
optionally its purpose.

Flow records each repository by its Bitbucket identifiers, not only its name,
so renaming the repository or the workspace in Bitbucket does not detach it.
With the app, Flow follows a rename as soon as Bitbucket reports it.

You can also attach a public repository on bitbucket.org without any
connection: pick **Public repository** and paste its URL. Flow clones it
anonymously, so agents can read it but cannot push or open pull requests.

## In a session

- Flow clones the source branch with every branch and the full commit history.
- Every `git fetch` and `git push` asks Flow for a credential through the
  credential helper; nothing goes into `.git/config` or the remote URL.
- There is no Bitbucket CLI. Agents use the `pull_request_*` tools.

## Pull-request tools

Sessions that hold a Bitbucket, GitHub or GitLab repository get these tools
automatically — the same set on every host:

| Tool | What it does |
| --- | --- |
| `pull_request_list` | Pull requests of a repository, by state or source branch |
| `pull_request_get` | One pull request: branches, head commit, reviewers, mergeability |
| `pull_request_changes` | The files it changes |
| `pull_request_checks` | The CI statuses on its head commit |
| `pull_request_create` | Opens a pull request (a draft unless told otherwise); returns the open one if the same branches already have one |
| `pull_request_update` | Title, description, target branch, draft, close or reopen |
| `pull_request_list_comments` | Comments, with threads and inline positions |
| `pull_request_add_comment` | A comment, a reply, or an inline comment on a file and line |
| `pull_request_review` | Approve, withdraw an approval, or request changes — never approve a pull request the same connection opened |
| `pull_request_merge` | Merges, only if the head commit is still the one the agent names |

Each write is recorded, so an agent repeating a call after a timeout gets the
first result instead of a second pull request or comment.
`pull_request_merge` refuses when the pull request moved past the commit the
agent reviewed, never bypasses approvals or branch restrictions, and can be
turned off for a connection. Bitbucket may finish a merge in the background;
the tool then reports it as pending.

---

## CI gates

A gate holds a board task until CI finishes (see
[Triggers and gates](/docs/triggers-and-gates)). For Bitbucket, an agent calls
`board_create_gate` with:

- `gate_type`: `bitbucket_pr_statuses_completed`
- `repository_id`: the Flow repository id;
- `pull_request_id`: the pull request number;
- `expected_commit` (recommended): the commit the gate waits on.

The gate resolves when every CI status Bitbucket shows on the pull request's
head commit has finished — Bitbucket Pipelines and any other CI that reports
build statuses. All successful passes; any failed or stopped fails. If the
pull request moves to another commit, the gate keeps waiting: a result about
other code is not the one it was created for.

With the app, Bitbucket tells Flow each time a build status changes, and the
gate resolves within a minute or so. With a token connection, the
reconciliation sweep checks the gate: every five minutes, once a gate has been
pending ten minutes. A gate with no result when its TTL runs out (12 hours by
default) is marked **stale**.

## Acting as yourself

By default an agent's pushes, pull requests and comments are the Bitbucket
connection's: the app's bot or the token's account. To have work in your own
name, connect your own Bitbucket account and let agents use it. (GitHub and
GitLab have the same:
[GitHub](/docs/github#acting-as-yourself), [GitLab](/docs/gitlab#acting-as-yourself).)

**Connect.** Open **Profile → Connected accounts** and press **Connect
Bitbucket**. Bitbucket asks you to authorize the operator's OAuth client; Flow
keeps the connection fresh for you. The button is offered only when the operator
has registered that client (the
procedure is `docs/operations/bitbucket-app.md` in the repository); otherwise
the card says connecting Bitbucket accounts is not configured. Only Bitbucket
Cloud is supported.

**Disconnect.** It removes the connection and the permissions below, but
**Bitbucket has no way to revoke the grant from outside**. The authorization stays
listed in your Atlassian account until you remove it there, and a token already
handed out works until it expires, at most two hours. Flow no longer holds a
refresh token afterwards.

**Allow it, per project.** The same tab lists your projects, with two switches
for each connected account. Both start off.

- **In my tasks:** agents may act as you in sessions you own.
- **In tasks that aren't mine:** an agent working for someone else in that project
  may take your token, when it names you.

**Give the agent the tool.** Whoever configures a step, a workflow or a session
adds the tool from the picker, under *Bitbucket as a user*. Flow never adds them
on its own.

| Tool | What it does |
| --- | --- |
| `bitbucket_user_token` | A token for the person the session runs for, and the identity to commit with |
| `bitbucket_user_token_for` | The same for another member of the company, given their `user_id` (from `board_list_members` or a task's `assignee_id`) |

Each tool returns the commit identity (`login`, `bitbucket_uuid`, `name` and
`email`) and a token, with the `host`, the `api_url`, the `git_username`
(`x-token-auth`) and the repositories it was checked for. Use the token for git
over HTTPS (username `x-token-auth`) and, in REST calls, as
`Authorization: Bearer` against `api_url`. The token expires within two hours;
`expires_at` says when to ask again, and it is earlier than Bitbucket's own
expiry. If Bitbucket refuses the token with 401, ask for it again. The agent
should use it only in the command that needs it: it is masked in session logs,
but it does enter the agent's context.

**The commit address is your real email.** Bitbucket has no noreply address, so
commits are made with your primary **confirmed** Bitbucket email, and anyone who
can read the repository's history sees it. An account with no confirmed primary
address cannot be used: the tool says so. If you do not want that, do not
connect.

**Your sessions share one token.** You have one Bitbucket token, not one per
session, so your concurrent sessions are handed the same value. Flow replaces it
only in the last ten minutes before it expires, because a refresh may end the
previous token. A token handed out then may have only a few minutes left: the
agent asks again.

**The token is not limited to the session's repositories.** Bitbucket cannot
narrow an OAuth token to chosen repositories: its scopes are fixed on the OAuth
client (account, email, repository read and write, pull request read and write).
So the token can do whatever you can do on Bitbucket, in every workspace you can
reach. Allowing it in a project allows your whole Bitbucket account in that
project's sessions. What bounds it instead: your own switches, your own access
(it can do nothing you cannot), the two-hour lifetime, and a record and masking
of every token handed out. Flow also checks, with your token, that you have
**write** or **admin** access to each of the session's Bitbucket repositories; one
you cannot push to is listed under `skipped` and left out of `repositories`.

**Your own request quota is spent.** Bitbucket limits REST calls per person
(1,000 an hour on repository endpoints, more on large paid workspaces), and calls
made with your token count against yours, together with your own work and your
other sessions. Agents should prefer git over HTTPS to the REST API.

The tool answers with a plain error when the person has not connected an account,
has not allowed it in this project, is not a member of the project, the session
has no user or no Bitbucket repository on an active connection, the account has
no confirmed primary email, or they cannot push to any of the repositories.

Flow decides none of how the token is used. Your instructions do, for example:

```bash
# token, email and name come from bitbucket_user_token
export GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" \
       GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL"
git commit -s -m "feat: ..."
git -c credential.helper= \
    -c credential.helper='!f() { echo username=x-token-auth; echo "password=$TOKEN"; }; f' \
    push origin HEAD:feature/x
curl -sS -H "Authorization: Bearer $TOKEN" -X POST "$API_URL/repositories/$WORKSPACE/$REPO/pullrequests" \
     -H "Content-Type: application/json" \
     -d '{"title":"...","source":{"branch":{"name":"feature/x"}}}'
```

## Limits

- Bitbucket Cloud only.
- The app reaches the whole workspace; per-repository narrowing needs
  repository access tokens.
- Pull request triggers ([Pull request events](/docs/triggers-and-gates#pull-request-events))
  need the app: an approval, a request for changes or a comment starts them,
  and a token connection sends no events. Pushes do not start workflows.
- Coder workspaces clone Bitbucket repositories with the connection's
  credential: a token connection hands over its own token, which reaches
  everything the token reaches ([Coder](/docs/coder#limits)).
- A repository renamed in Bitbucket while a session is running keeps its old
  address in that session's checkout, and its fetches and pushes stop
  authenticating. The next session clones it under the new name.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| The dialog says the token was refused | Mistyped, expired or revoked token, or missing scopes | Create a token with the scopes above and paste it again |
| *The Aixle Flow app on Bitbucket workspace … has not delivered a usable token* | The app has not reported for over two hours, or was just installed | Check the app is still installed. Operator: check that Bitbucket can reach the deployment |
| *The Aixle Flow app was removed from this workspace* | A workspace admin uninstalled the app | Install it again and connect from **Workspace settings → Aixle Flow** |
| *This Bitbucket workspace is no longer connected to this company* | Someone disconnected it in Bitbucket | Connect it again |
| The connect page says the link expired or was used | Links work once, for ten minutes | Select **Connect** in Bitbucket again |
| After signing in, the connect page says it opens from Bitbucket | The browser refused to keep the link while you signed in | Select **Connect** in Bitbucket again; you are signed in now |
| Clones and gates stopped after an app update | The update needs new permissions and waits for a workspace admin | A workspace admin approves the app's update in Bitbucket |
| A push is refused | Branch restrictions do not allow the app's bot or the token's identity | Allow it on that branch, or push to another branch and open a pull request |
| Gates resolve only after ten minutes or more | A token connection (no events), or the app has gone quiet | Use the app; check the integration row's last-heard time |
