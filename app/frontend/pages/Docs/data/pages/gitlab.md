# Connecting GitLab

GitLab connects per Flow project with a personal access token, and the
connection acts as the person the token belongs to. From then on:

- you attach the GitLab projects that person is a member of as
  **repositories**;
- agents clone, fetch and push them in their sessions, without the token ever
  sitting in the checkout;
- Flow registers a pipeline hook on each attached project, so a CI gate on a
  board task resolves as soon as its pipeline finishes.

That is the whole integration. There are no GitLab tools for merge requests or
issues and no GitLab triggers. There is no OAuth app either, so you register
nothing in GitLab and set no `GITLAB_APP_*` variable.

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
- add and remove a pipeline hook on each attached project. This needs the
  **Maintainer** role on that project. Without it the repository is still
  added, but its gates resolve later (see [CI gates](#ci-gates)).

The token cannot be narrowed per call. Every session that works on one of these
repositories gets the token itself, with everything it can reach. Pushes are
made as the token's owner, with that person's permissions. Prefer a token from
an account kept for Flow, with access to the projects you mean to attach and
nothing else.

Flow never checks the token again after you connect. Once it expires or is
revoked, the row still says **Active** but clones start failing. Keep track of
the expiry date.

## Connect

1. On the project's **Integrations** page choose **Connect → GitLab**.
2. Paste the token into **Personal Access Token** and select **Connect**.

Flow asks GitLab who the token belongs to. If GitLab accepts the token, the
connection appears under that GitLab username with status **Active**. If GitLab
refuses it, the page shows `GitLab token verification failed: …` and leaves a
row named **GitLab (unverified)** in error. Remove that row and connect again
with a token that works.

If you connect again, Flow adds a second connection and leaves the first one in
place. See [Replacing the token](#replacing-the-token).

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
- No GitLab CLI is authenticated. GitHub sessions get a `gh` that is signed in,
  but GitLab sessions get only git. Flow has no merge-request tools.

---

## CI gates

A **gate** holds a board task until CI finishes (see
[Triggers and gates](/docs/triggers-and-gates)). For GitLab, an agent in a
workflow step calls `board_create_gate` with:

- `gate_type`: `gitlab_pipeline_completed`
- `repo_full_name`: the repository as Flow lists it, for example
  `group/subgroup/app`. It must be attached to the task's project.
- `pipeline_id`: the GitLab pipeline id.

The tool does not list `pipeline_id` among the parameters it advertises, so
name that parameter in the step's instructions.

### The pipeline hook

When you add a GitLab repository, Flow gives the GitLab project a hook at
`https://<your domain>/webhooks/gitlab`. The hook carries **Pipeline events**
only and has its own secret token. Before adding it, Flow deletes any earlier
hook this deployment put on that project, because the old secret no longer
matches. Removing the repository from Flow deletes the hook.

GitLab calls the hook each time a pipeline changes status. When the pipeline
finishes as `success`, `failed` or `canceled`, the gate waiting on it resolves.
`success` passes, and the other two fail.

The hook can be missing: the token's user may not be a Maintainer, or GitLab
may not be able to reach your domain. In that case Flow adds the repository
anyway and shows no warning. Gates still resolve, but later, through the
reconciliation sweep:

- Every five minutes, Flow asks GitLab about the gates that have been pending
  for at least ten minutes. It asks about each gate at most once every ten
  minutes.
- A finished pipeline resolves its gate the same way it would through the hook,
  and `skipped` counts as a pass.
- Pipelines that are running, `manual` or `scheduled` keep the gate waiting.
- If GitLab says the pipeline does not exist, the gate is marked **stale** at
  once. A gate that has no result when its TTL runs out (12 hours by default)
  is marked stale too.

Nothing in GitLab starts a workflow. The hook carries only pipeline events, and
Flow uses them only for gates. There is no GitLab trigger.

## Replacing the token

A GitLab connection has no edit and no **Test connection**. A new token means a
new connection, and its repositories have to move to that connection:

1. Connect again with the new token.
2. On **Repositories**, remove the repositories attached through the old
   connection. Each removal deletes its GitLab hook.
3. Remove the old connection on **Integrations**.
4. Add the repositories again from the new connection, and add them back to the
   steps that listed them.

Do step 2 before step 3. A repository cannot be attached twice in one project.
Removing a connection does remove its repositories, but it does not delete
their GitLab hooks. Those hooks stay in GitLab, and every call they make gets a
401, until someone deletes them there.

---

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
  from the deployment's own `PROTOCOL` and `DOMAIN`. GitLab must be able to
  reach that address. There is no separate setting for the webhook host.
- **Public repository** still means gitlab.com only.

Sessions get the token from Flow's credential endpoint, `GIT_CREDENTIALS_URL`,
which by default is on the internal network. Never point it at a public host,
because each request carries a key for that session. See
[Configuration](/docs/configuration).

## Limits

- The only way to connect is a personal access token, which acts as its owner.
  There is no OAuth app and no group-level install.
- Each deployment reaches one GitLab instance.
- Each GitLab project carries one Flow hook per deployment. If another Flow
  project, in any company on the deployment, already attached the same GitLab
  project, attaching it again replaces the first hook. The first project's
  gates then resolve only through the sweep. Removing either repository removes
  the one hook that is left.
- There are no merge-request tools, no GitLab CLI and no GitLab triggers.
  GitLab issues cannot be used as a tracker: [Trackers](/docs/trackers)
  supports Jira and Azure Boards.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `GitLab token verification failed: …` and a **GitLab (unverified)** row in error | GitLab refused the token because it was mistyped, has expired or was revoked | Remove the row. Connect with a new token that has the `api` scope |
| Connect fails with a server error and no row is saved | Flow could not reach GitLab, or `GITLAB_ENDPOINT` is not a GitLab API URL | Operator: check `GITLAB_ENDPOINT`, including `/api/v4` |
| The **Repository** picker is empty | The token's user is not a member of any project, or GitLab refused the token | Check the user's project memberships. Replace an expired token |
| An agent says a repository is missing from its session | The clone failed. Flow leaves failed clones out of what it tells the agent; the session page lists them under *did not clone*, with the reason. Usual causes: the token expired or was revoked, the user lost access, the source branch is gone, or the container cannot reach the GitLab host | Fix the cause. The next session clones again |
| `git fetch` or `git push` fails to authenticate mid-session | The token expired or was revoked. On self-managed GitLab, GitLab may be served over HTTP | Replace the token. Serve GitLab over HTTPS |
| Gates resolve ten minutes or more after the pipeline ends | The hook is missing: the token's user is not a Maintainer, GitLab cannot reach your domain, or another Flow project attached the same GitLab project later | Using a token with the Maintainer role, remove the repository, add it again, then add it back to the steps that listed it |
| Gate goes stale with `CI pipeline <id> on <repo> cannot be read: pipeline <id> not found in <repo>` | Wrong pipeline id or repository path | Create the gate again with the right values |
| Gate goes stale with `no CI result after …` | The pipeline was still running or waiting on a manual job, or GitLab could not be read for the whole TTL | Check the pipeline. If the last probe names `Gitlab::Error::Unauthorized`, the token stopped working |
| GitLab's hook log shows `401` responses | A leftover hook. Its repository was removed together with the connection, or Flow could not delete the hook | Delete that hook in GitLab |
