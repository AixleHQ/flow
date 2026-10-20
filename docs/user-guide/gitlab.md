# Connecting GitLab

GitLab connects per Flow project in one of two ways:

- **Sign in with GitLab** (recommended, where the operator set up the OAuth app).
  An Owner of a GitLab group signs in once. Flow creates a **service account**
  in that group and from then on acts as that account, never as a person. See
  [Sign in with GitLab](#sign-in-with-gitlab).
- **A token** you paste, which acts as whoever it belongs to. See
  [The token](#the-token).

From then on:

- you attach the GitLab projects that person is a member of as
  **repositories**;
- agents clone, fetch and push them in their sessions, without the token ever
  sitting in the checkout;
- agents open, review, comment on and merge merge requests with the
  `pull_request_*` tools;
- Flow registers a pipeline hook on each attached project, so a CI gate on a
  board task resolves as soon as its pipeline finishes.

- GitLab projects you pick become **trackers**: their issues start workflows
  and agents work on them with the `tracker_*` tools. See
  [GitLab issues as a tracker](#gitlab-issues-as-a-tracker).

## Who does what

- Any member who can change the project connects GitLab; viewers cannot.
- Anyone who can edit the project adds repositories from the connection.
- For a self-managed GitLab, the operator sets `GITLAB_ENDPOINT` once for the
  deployment. See [Self-managed GitLab](#self-managed-gitlab).

---

## The token

In GitLab, create a **personal access token** with the `api` scope. That is the
scope the connect dialog asks for. Flow uses the token to:

- read the user it belongs to, which checks the token and names the connection;
- list the projects that user is a member of, and their branches, for the
  repository picker;
- clone, fetch and push over HTTPS as that user;
- open, update, comment on, approve and merge merge requests;
- add and remove a pipeline hook on each attached project. This needs the
  **Maintainer** role on that project. Without it the repository is still
  added, but its gates resolve later (see [CI gates](#ci-gates)).

The token cannot be narrowed per call. Every session that works on one of these
repositories gets the token itself, with everything it can reach. Pushes,
merge requests, comments, approvals and merges are made as the token's owner,
with that person's permissions. Prefer a **project or group access token**:
GitLab makes it a bot user, so agents' work never appears under a colleague's
name, and it reaches only that project or group. A personal token from an
account kept for Flow works too.

Flow checks the token when you connect, when you replace it, and when you
select **Test connection** on the row. In between, a token that expires or is
revoked goes unnoticed: the row still says **Active** while clones fail.
**Test connection** then marks the row **Error**. Keep track of the expiry
date.

## Sign in with GitLab

1. On the project's **Integrations** page choose **Connect → GitLab**, then
   **Sign in with GitLab**.
2. Sign in to GitLab as an **Owner** of the group whose projects Flow should
   reach, and approve Aixle Flow. It asks for the `api` scope.
3. Back on the Integrations page, pick the group. Flow:
   - creates a service account named **Aixle Flow** (`aixle-flow-…`) in it;
   - makes it a **Maintainer** of the group;
   - gives it a token with the `api` scope.

   From then on, Flow keeps only that token and drops yours.
4. Flow then opens **Issue boards**, to make projects' issues a tracker (see
   [GitLab issues as a tracker](#gitlab-issues-as-a-tracker)). Close it if
   GitLab is only your code host.

The connection is named after the group, and everything Flow does in GitLab is
done by the service account: clones and pushes, merge requests, issue comments
and moves.

- **What it can reach.** The service account sees the group's projects and its
  subgroups'. To reach a project elsewhere, invite the account there in GitLab.
- **Seats.** A service account takes no seat. GitLab allows 100 per top-level
  group on Free; GitLab.com has them on every tier since GitLab 18.11.
- **Who can do it.** On GitLab.com, a service account in a top-level group can
  be created only by that group's Owner; a subgroup's Owner can create one in
  the subgroup.
- **Expiry.** If the group requires tokens to expire, the token lasts up to a
  year. Flow rotates it a month before it ends, so nobody has to. If the group
  does not require it, the token does not expire.
- **Signing in again** for the same group renews that connection, and its
  repositories and trackers stay.

## Connect with a token

1. On the project's **Integrations** page choose **Connect → GitLab**.
2. Paste the token into **Personal Access Token** and select **Connect**.

Flow asks GitLab who the token belongs to. If GitLab accepts the token, the
connection appears under that GitLab username with status **Active**. If GitLab
refuses the token, or cannot be reached, the dialog stays open, says why, and
nothing is saved.

Connecting again with a token for the same GitLab account updates that
account's connection: the new token replaces the old one, and its repositories
stay attached. A token for another account adds a second connection.

## Attaching repositories

On **Repositories → Add Repository**, keep **From integration** and fill in:

1. **Integration**: the connection, listed as `<username> (GitLab)`.
2. **Repository**: one of the GitLab projects the token's user is a member of,
   such as `group/project` or `group/subgroup/project`. Repositories already
   attached to the project are not offered.
3. **Source branch**: the branch sessions check out. It starts as the GitLab
   project's default branch.
4. **Purpose** (optional): tells agents what the repository is for.

Then select **Add Repository**, and Flow registers the pipeline hook on that
GitLab project.

You can also attach a public project on gitlab.com without any connection: pick
**Public repository** and paste its URL. Flow clones it anonymously, so agents
can read it but cannot push, and it gets no hook. See
[Repositories](/docs/repositories).

## In a session

A session gets a repository when its step lists one
([Repositories](/docs/repositories)).

- Flow clones the source branch with every branch and the full commit history.
  File contents from other revisions download the first time they are used.
- The clone authenticates with a request header. The checkout is left with a
  clean remote and a credential helper, so every later `git fetch` and
  `git push` asks Flow for the credential. Nothing goes into `.git/config` or
  the remote URL, and agents are told not to put credentials there.
- No GitLab CLI is authenticated. GitHub sessions get a `gh` that is signed in;
  GitLab sessions get git and the `pull_request_*` tools instead.

## Merge-request tools

Sessions that hold a GitLab repository get these tools automatically. They are
the same tools GitHub and Bitbucket repositories get, so a workflow written for
one host runs on the others.

| Tool | What it does |
| --- | --- |
| `pull_request_list` | Merge requests of a repository, by state or source branch |
| `pull_request_get` | One merge request: branches, head commit, reviewers, mergeability |
| `pull_request_changes` | The files it changes |
| `pull_request_checks` | The head pipeline and the commit statuses on its head commit |
| `pull_request_create` | Opens a merge request, as a draft unless told otherwise; returns the open one if the same branches already have one |
| `pull_request_update` | Title, description, target branch, draft, close or reopen |
| `pull_request_list_comments` | Notes and discussions, with inline positions |
| `pull_request_add_comment` | A note, a reply in a discussion, or an inline comment on a file and line |
| `pull_request_review` | Approve or withdraw an approval, never on a merge request the same connection opened. *Request changes* is not offered on GitLab yet |
| `pull_request_merge` | Merges, only if the head commit is still the one the agent names |

`pull_request` takes the merge request's number (its `iid`, `!123`) or its URL.
`target_branch` defaults to the repository's source branch in Flow. A run
started from a tracker issue gets the issue key at the start of the title.

Each write is recorded, so an agent repeating a call after a timeout gets the
first result instead of a second merge request or comment.
`pull_request_merge` refuses when the merge request moved past the commit the
agent reviewed — Flow checks, and GitLab checks the same commit again — and
never bypasses approval rules or protected branches. GitLab merges with the
project's own merge method; `fast_forward` cannot be asked for.

---

## CI gates

A **gate** holds a board task until CI finishes (see
[Triggers and gates](/docs/triggers-and-gates)). For GitLab, an agent in a
workflow step calls `board_create_gate` with:

- `gate_type`: `gitlab_pipeline_completed`
- `repo_full_name`: the repository as Flow lists it, for example
  `group/subgroup/app`. It must be attached to the task's project.
- `pipeline_id`: the GitLab pipeline id, `CI_PIPELINE_ID` inside the
  pipeline or the number at the end of its `/-/pipelines/<id>` URL. The
  per-project `iid` does not work.

### The pipeline hook

When you add a GitLab repository, Flow gives the GitLab project a hook at
`<PROTOCOL>://<DOMAIN>/webhooks/gitlab`, or under `GITLAB_WEBHOOK_BASE_URL`
when the operator sets it. The hook carries **Pipeline events** only and has
its own secret token. Each repository owns its hook: when several Flow
projects, in one company or in several, attach the same GitLab project, each
one gets a hook of its own. Removing the repository from Flow, or the GitLab
connection it came through, deletes that repository's hook and no other.

GitLab calls the hook each time a pipeline changes status. When the pipeline
finishes as `success`, `failed`, `canceled` or `skipped`, the gate waiting on
it resolves. `success` and `skipped` pass, and the other two fail.

The hook can be missing. The token's user may not be a Maintainer, or GitLab
may not be able to reach the hook address. When that address is a loopback or
private host (`localhost`, `10.x`, `*.internal` and the like) and GitLab is
not on a private network itself, Flow registers no hook at all and says so
once in the server log. Either way Flow adds the repository and shows no
warning. Gates still resolve, but later, through the reconciliation sweep:

- Every five minutes, Flow asks GitLab about the gates that have been pending
  for at least ten minutes. It asks about each gate at most once every ten
  minutes.
- A finished pipeline resolves its gate the same way it would through the hook.
- Pipelines that are running, `manual` or `scheduled` keep the gate waiting.
- If GitLab says the pipeline does not exist, the gate is marked **stale** at
  once. A gate that has no result when its TTL runs out (12 hours by default)
  is marked stale too.

Nothing in GitLab starts a workflow. The hook carries only pipeline events, and
Flow uses them only for gates. There is no GitLab trigger.

## Replacing the token

Select **Replace token** on the row and paste the new token. Flow asks GitLab
about it first, and only a token GitLab accepts replaces the old one. The
connection keeps its repositories, their hooks and the steps that use them. If
the new token belongs to another GitLab account, the connection acts as that
account from then on and takes its name; an account that already has another
connection in the project is refused.

**Test connection** on the row asks GitLab about the stored token and changes
nothing else. If GitLab refuses it, the row turns **Error** with *GitLab no
longer accepts this connection's token. Replace the token.* If GitLab cannot be
reached, the row stays as it was.

To move the repositories to another account's connection instead:

1. Connect GitLab with that account's token.
2. On **Repositories**, remove the repositories attached through the old
   connection. Each removal deletes its GitLab hook.
3. Remove the old connection on **Integrations**.
4. Add the repositories again from the new connection, and add them back to the
   steps that listed them.

Do step 2 before step 3. A repository cannot be attached twice in one project.
Removing a connection also removes its repositories and deletes their GitLab
hooks.

---

## GitLab issues as a tracker

Any GitLab connection can make its projects' issues a tracker, like a Jira
project. What trackers are and how their triggers work is on
[Trackers](/docs/trackers).

1. On the connection's row on the **Integrations** page select **Issue boards**
   (the board icon). It also opens right after a sign-in.
2. Pick the projects, and for each the **board** whose label lists are its
   columns.

Each project becomes a tracker on the project's **Trackers** page.

- **Columns** are **Open**, then the board's label lists in board order, then
  **Closed**. An issue is in Closed when it is closed. Otherwise it is in the
  first list whose label it carries, or in Open when it carries none of them.
- **Moving an issue** adds the target list's label, removes the other lists'
  labels, and closes or reopens the issue for Closed. Without a board, the
  columns are only Open and Closed.
- **Issues** are keyed `group/project#12`. Agents can also pass `#12` (in the
  tracker's project) or the issue's URL.
- **Assignees** are GitLab usernames of the project's members.
- **Events.** Flow adds a webhook to each tracked project for issue and comment
  events, which needs the **Maintainer** role there. Confidential issues and
  internal notes start nothing.
- **Files** are the uploads an issue's description and comments link to. Files
  on a confidential issue or in an internal note are never copied. Files an
  agent sends are uploaded to the project and linked from a comment.
- **Who the writes are from.** With **Sign in with GitLab**, writes come from
  the service account, and `@aixle-flow-…` in a comment mentions Flow. With a
  token, writes come from whoever the token belongs to.

GitLab's work item **Status** field (Premium) is not used as columns yet. Use
label lists on a board.

## Self-managed GitLab

Each deployment talks to one GitLab instance, which is gitlab.com unless the
operator sets another:

```bash
GITLAB_ENDPOINT=https://gitlab.example.com/api/v4
```

- Give the API URL, including `/api/v4`. Flow clones from the same host with
  that suffix removed.
- Every GitLab connection on the deployment uses this instance, so one
  deployment cannot reach gitlab.com and a self-managed instance at the same
  time.
- The Flow server calls the API, and the session containers clone and push.
  Both must be able to reach the host.
- Serve GitLab over HTTPS. The credential helper only answers for `https`
  remotes. Over plain HTTP the first clone works, but every later fetch or push
  fails to authenticate.
- The pipeline hook points at `<PROTOCOL>://<DOMAIN>/webhooks/gitlab`, built
  from the deployment's own `PROTOCOL` and `DOMAIN`, unless
  `GITLAB_WEBHOOK_BASE_URL` names another base URL. GitLab must be able to
  reach that address. A GitLab on a private host may use a private address
  for it; a GitLab on a public host gets no hook at a private one.
- **Public repository** still means gitlab.com only.
- **Sign in with GitLab** needs an OAuth application on the instance. An
  administrator creates it under **Admin → Applications → New application**:
  - redirect URI `<PROTOCOL>://<DOMAIN>/integrations/gitlab/oauth/callback`;
  - scope `api`;
  - **Trusted** ticked.

  Give its id and secret to the operator as `GITLAB_OAUTH_CLIENT_ID` and
  `GITLAB_OAUTH_CLIENT_SECRET`. On gitlab.com, the deployment's operator
  registers the application under a group's **Settings → Applications**, with
  the same redirect URI and scope.

Sessions get the token from Flow's credential endpoint, `GIT_CREDENTIALS_URL`,
which by default is on the internal network. Never point it at a public host,
because each request carries a key for that session. See
[Configuration](/docs/configuration).

## Limits

- The only way to connect is a personal access token, which acts as its owner.
  There is no OAuth app and no group-level install.
- Each deployment reaches one GitLab instance.
- A repository attached before Flow kept track of each hook can leave its
  hook in GitLab when it is removed: Flow cannot tell that hook apart while
  another such repository attaches the same GitLab project.
- There is no GitLab CLI and there are no GitLab triggers. GitLab issues
  cannot be used as a tracker: [Trackers](/docs/trackers) supports Jira, Azure
  Boards, GitHub Projects, Linear and YouTrack.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| *GitLab rejected this token* or *GitLab refused this token* in the dialog | The token was mistyped, has expired, was revoked, or lacks the `api` scope | Create a token with the `api` scope and paste it again |
| *Could not reach GitLab at …* or *… did not answer as a GitLab API* in the dialog | Flow could not reach GitLab, or `GITLAB_ENDPOINT` is not a GitLab API URL | Operator: check `GITLAB_ENDPOINT`, including `/api/v4` |
| A row in **Error** saying *GitLab no longer accepts this connection's token* | **Test connection** found the token expired or revoked | **Replace token** on the row |
| The **Repository** picker is empty | The token's user is not a member of any project, or GitLab refused the token | Check the user's project memberships. Replace an expired token |
| An agent says a repository is missing from its session | The clone failed. Flow leaves failed clones out of what it tells the agent; the session page lists them under *did not clone*, with the reason. Usual causes: the token expired or was revoked, the user lost access, the source branch is gone, or the container cannot reach the GitLab host | Fix the cause. The next session clones again |
| `git fetch` or `git push` fails to authenticate mid-session | The token expired or was revoked. On self-managed GitLab, GitLab may be served over HTTP | Replace the token. Serve GitLab over HTTPS |
| Gates resolve ten minutes or more after the pipeline ends | The hook is missing: the token's user is not a Maintainer, or GitLab cannot reach the hook address. A loopback or private address registers no hook, and the server log says so | Operator: set `GITLAB_WEBHOOK_BASE_URL` to an address GitLab can reach. Then, using a token with the Maintainer role, remove the repository, add it again, and add it back to the steps that listed it |
| Gate goes stale with `CI pipeline <id> on <repo> cannot be read: pipeline <id> not found in <repo>` | Wrong pipeline id or repository path | Create the gate again with the right values |
| Gate goes stale with `no CI result after …` | The pipeline was still running or waiting on a manual job, or GitLab could not be read for the whole TTL | Check the pipeline. If the last probe names `Gitlab::Error::Unauthorized`, the token stopped working |
| GitLab's hook log shows `401` responses | A leftover hook. Flow could not delete it when its repository was removed, or the repository was attached before Flow kept track of each hook | Delete that hook in GitLab |
