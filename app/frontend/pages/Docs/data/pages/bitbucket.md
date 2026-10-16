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

1. On the project's **Integrations** page choose **Connect → Bitbucket**, keep
   **Install the app**, and type the workspace (the part after
   `bitbucket.org/`).
2. If the company has already connected that workspace, the project is
   connected and you are done. Otherwise Flow shows the install link.
3. A workspace admin opens the link, picks the workspace and approves what the
   app asks for.
4. In Bitbucket, the admin opens **Workspace settings → Aixle Flow** and selects
   **Connect**. Bitbucket opens Flow.
5. Flow shows the workspace, who started the connection and the project to
   connect it to. Sign in if asked, check them and select **Connect**.

The workspace is now connected to the Flow company. Further projects in that
company connect by typing the workspace on their own **Integrations** page —
no trip to Bitbucket. One workspace belongs to one Flow company at a time.

**Workspace settings → Aixle Flow** keeps showing which Flow company and
projects the workspace is connected to, and by whom. **Disconnect** there
unbinds it: every Flow project using it stops reaching the workspace until it
is connected again. The connect link Flow hands out works once, for ten
minutes; never send it to anyone.

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
3. On **Integrations** choose **Connect → Bitbucket → Use a token**, type the
   workspace, paste the token and select **Connect**.

Flow works out which kind of token it is and checks it before saving anything.
Connecting again with a token for the same identity replaces the old token and
keeps the repositories attached. **Test connection** on the row asks Bitbucket
about the stored token; **Replace token** swaps it.

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

## Limits

- Bitbucket Cloud only.
- The app reaches the whole workspace; per-repository narrowing needs
  repository access tokens.
- No Bitbucket triggers: push and pull-request events do not start workflows.
- Coder workspaces cannot clone Bitbucket repositories yet.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| The dialog says the token was refused | Mistyped, expired or revoked token, or missing scopes | Create a token with the scopes above and paste it again |
| *The Aixle Flow app on Bitbucket workspace … has not delivered a usable token* | The app has not reported for over two hours, or was just installed | Check the app is still installed. Operator: check that Bitbucket can reach the deployment |
| *The Aixle Flow app was removed from this workspace* | A workspace admin uninstalled the app | Install it again and connect from **Workspace settings → Aixle Flow** |
| *This Bitbucket workspace is no longer connected to this company* | Someone disconnected it in Bitbucket | Connect it again |
| The connect page says the link expired or was used | Links work once, for ten minutes | Select **Connect** in Bitbucket again |
| A push is refused | Branch restrictions do not allow the app's bot or the token's identity | Allow it on that branch, or push to another branch and open a pull request |
| Gates resolve only after ten minutes or more | A token connection (no events), or the app has gone quiet | Use the app; check the integration row's last-heard time |
