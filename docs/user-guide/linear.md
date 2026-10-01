# Connecting Linear

Linear connects per Flow project. A connection names one Linear workspace and
the teams you pick in it, and each of those teams becomes a **tracker** on the
project's **Trackers** page. From then on:

- tracker triggers start workflows when an issue is created, moves to another
  state, is assigned, or gets a comment;
- agents read and change issues with the `tracker_*` tools — search, create,
  update, move, assign, comment — and only in the teams you picked.

There are two ways to connect, and they differ in **who Flow acts as** in Linear.

| | Aixle's Linear app | API key |
| --- | --- | --- |
| Who connects | A Linear workspace admin installs the app | Anyone with a Linear API key |
| Flow acts as | The app itself, shown as the app in Linear | The key's owner |
| Webhooks for triggers | The app's own webhook; nothing to set up | One per team, registered by Flow — only with a workspace admin's key |
| Needs | The deployment's Linear app (always there on Aixle SaaS) | Nothing on the deployment |

If people's own edits should never look like Flow's, install the app, or use
the API key of an account kept for Flow.

---

## With Aixle's Linear app

1. On the project's **Integrations** page choose **Connect → Linear**, keep
   **Aixle app**, and select **Install Aixle's Linear app**.
2. Sign in as a workspace admin and approve the app. Linear installs it for the
   whole workspace, acting as the app rather than as you.
3. Back in Flow, pick the teams to connect.

The app writes as itself, so its changes are always Flow's own, and nothing
has to be marked as kept for Aixle. Its events arrive through the app's own
webhook, which Linear sets up for every workspace that installs it; there is
nothing to register.

Linear does not offer the app in its mention picker or as an assignee — that
takes Linear's agent features, which Flow does not use. A comment that types
the app's username as `@name` still counts as mentioning it, but the dependable
way into a workflow is a state move
([Connect a board column](/docs/trackers#connect-a-board-column)) or a new
issue. If you want "assign it to Aixle" to start work, connect with the API key
of an account kept for Flow instead.

Reconnecting (the same steps again) renews the authorization in place: the
trackers and their triggers stay.

## With an API key

1. Sign in to Linear as the account Flow should act as — best one kept for
   Flow — and create a personal API key under
   **Settings → Account → Security & access**.
2. In Flow: **Connect → Linear → API key**, paste the key, select **Check**,
   and pick the teams.
3. Tick **This Linear account is kept for Aixle** only when it is: Flow then
   treats that account's changes as its own, and a comment that mentions it
   matches a trigger's "mentions Aixle" condition. Leave it off for your own
   key — otherwise your own edits would be ignored by triggers set to ignore
   changes Aixle made.

### The webhooks

When the project gets its first tracker trigger, Flow registers one webhook
per connected team, pointed at its own URL and signed with a secret Flow
generates. Linear lets only a **workspace admin's** key manage webhooks:

- with an admin's key, triggers work without anything else to do;
- with any other key, the tools work, but triggers do not fire. The
  connection's row says *"Only a Linear workspace admin's API key can register
  webhooks"*. Connect with an admin's key, or install the app.

**Test connection** tries a webhook that could not be registered again and
says what is still not delivering. Linear has to reach the deployment's
domain; with a loopback or private host, Flow registers no webhooks.

---

## Teams and states

A tracker is a Linear team. Its statuses are the team's workflow states — what
the columns of the team's board are — and each state's type gives its portable
category:

| Linear state type | Category |
| --- | --- |
| Triage, Backlog, Unstarted | `todo` |
| Started | `in_progress` |
| Completed | `done` |
| Canceled, Duplicate | `canceled` |

A trigger's **Status** condition names a state, such as "Ready for AI".
`tracker_transition_issue` takes a state's name or id.

## Tools

- **Issue references** — an identifier such as `ENG-123`, the issue's id, or
  its URL in this workspace.
- **Issue type** — Linear has one, `Issue`. Teams use labels for kinds of work.
- **Labels** — by name, among the team's and the workspace's labels. A name
  Linear does not have is refused, and the error lists the labels there are;
  Flow does not create labels.
- **People** — by name, username, email or id; it must match exactly one
  member of the team. `none` clears the assignee. `tracker_list_users` lists
  the team's active members.
- **Extra fields** — `priority`, from 0 (none) and 1 (urgent) to 4 (low).
- **Search** — by text in the title, state, assignee, labels or ids; `open_only`
  leaves out completed, canceled and duplicate issues. There is no
  `native_query`: Linear's filters are structured.
- Linear issues have no revision number, so `expected_revision` is refused.

An **Issue is assigned** trigger fires when an issue gets an assignee, not when
the assignee is cleared.

---

## Self-hosted: the Linear app

Without an app, a self-hosted deployment offers only the API-key connection. To
offer the app, the operator creates one OAuth application for the whole
deployment at
[linear.app/settings/api/applications](https://linear.app/settings/api/applications):

1. **Callback URL:** `https://<your domain>/integrations/linear/oauth/callback`.
2. **Webhooks:** turn them on, URL
   `https://<your domain>/webhooks/trackers/app/linear`, with **Issues** and
   **Comments**. Copy the signing secret Linear shows.
3. If workspaces other than yours will install it, make it public.
4. Configure Flow:

   ```bash
   LINEAR_OAUTH_CLIENT_ID=<client id>
   LINEAR_OAUTH_CLIENT_SECRET=<client secret>
   LINEAR_WEBHOOK_SECRET=<the webhook signing secret>
   ```

   Set `LINEAR_WEBHOOK_BASE_URL` only when the deployment's domain is not
   reachable from Linear (a tunnel in development). It is where API-key
   connections' webhooks point; a loopback or private host registers none.

Use one app per deployment: its webhook has one URL, and Flow routes each
delivery to the connections of the workspace it names.

## When something is wrong

- **Test connection** on the row re-reads the workspace and the teams, and
  retries webhooks that could not be registered.
- *"This connection can no longer see …"* — the account lost access to a team.
  Give it back in Linear, or take the team off the connection.
- *"Linear no longer accepts this connection's authorization. Reconnect
  Linear."* — the app was uninstalled or its access revoked. *"Linear rejected
  this connection's API key"* — the key was deleted. Either way, connect again;
  the trackers stay.
- Triggers never fire on an API-key connection — see [The webhooks](#the-webhooks).
