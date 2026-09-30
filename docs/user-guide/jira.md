# Connecting Jira

Jira Cloud connects per Flow project. A connection names one Jira site and the
Jira projects you pick on it, and each of those projects becomes a **tracker**
on the project's **Trackers** page. From then on:

- tracker triggers start workflows when an issue is created, moves to a column,
  is assigned, or gets a comment;
- agents read and change issues with the `tracker_*` tools — search, create,
  update, move, assign, comment — and only in the projects you picked.

There are two ways to connect, and they differ in **who Flow acts as** in Jira.

| | Atlassian account | Service account |
| --- | --- | --- |
| Who connects | Anyone who can sign in to the site | An Atlassian organization admin creates the credential |
| Flow acts as | The account that signed in | The service account |
| Webhooks for triggers | Registered automatically | A Jira admin adds one by hand |
| Needs | The deployment's Atlassian app (always there on Aixle SaaS) | Nothing on the deployment |

If people's own edits should never look like Flow's, sign in with an account
kept for Flow, or use a service account.

---

## With an Atlassian account

1. On the project's **Integrations** page choose **Connect → Jira**, keep
   **Atlassian account**, and select **Continue to Atlassian**.
2. Sign in, pick the site, and accept the permissions.
3. Back in Flow, pick the Jira projects to connect. If the account can reach
   several sites, pick the site first.
4. Tick **This Atlassian account is kept for Aixle** only when it is: Flow
   then treats that account's changes as its own, and a comment that mentions
   it matches a trigger's "mentions Aixle" condition. Leave it off when you
   signed in as yourself — otherwise your own edits would be ignored by
   triggers set to ignore changes Aixle made.

When a project gets its first tracker trigger, Flow registers a webhook on the
site for the connected projects. Jira expires such webhooks after 30 days; Flow
renews them daily. Atlassian allows five per app, user and site, so connecting
the same site from more than five Flow projects as one person runs out.

Reconnecting (the same steps again) renews the authorization in place: the
trackers and their triggers stay.

## With a service account

An Atlassian organization admin does this part once:

1. In **admin.atlassian.com → Directory → Service accounts**, create a service
   account and give it access to Jira and to the projects Flow should work in
   (Browse projects, Create, Edit, Transition, Assign issues, Add comments).
2. Create an **OAuth 2.0** credential for it with these scopes:
   - `read:jira-work`, `write:jira-work`, `read:jira-user`
   - `read:board-scope:jira-software`, `read:board-scope.admin:jira-software`,
     `read:project:jira` — for the board's columns
3. Copy the client ID and secret.

Then in Flow: **Connect → Jira → Service account**, enter the site (for example
`your-team.atlassian.net`), the client ID and the secret, select **Check**, and
pick the Jira projects.

### The webhook

Only apps may register webhooks in Jira, so for a service-account connection a
**Jira admin** adds one for tracker triggers to fire (the tools work without it):

1. In Flow, select **Webhook setup** on the connection's row. It shows the URL,
   the secret, a JQL filter for the connected projects, and the events.
2. In Jira, open **Settings → System → WebHooks → Create a WebHook**, enter
   the URL and the secret, paste the JQL, tick **Issue: created**,
   **Issue: updated** and **Comment: created**, and save.

The dialog shows when the last event arrived, which is the quickest way to
check the webhook works.

---

## Board columns are the status

A tracker's statuses are the columns of the Jira project's board — what people
see and move cards between — not the workflow statuses underneath:

- A trigger's **Status** condition names a column, such as "Ready for AI".
- A move between two workflow statuses inside one column moves nothing on the
  board and starts nothing.
- The workflow status is still there as `fields.state`, and in an event as
  `change.state`.
- An agent can move an issue to a column, a workflow status, or by the name of
  a Jira transition; a column is reached through any transition into one of its
  statuses.

The first board of the project is used. A project with no board has only its
workflow statuses.

## Tools

Agents address people by name or email; when a name matches more than one
person, `tracker_list_users` lists who an issue can be assigned to. Jira issues
have no revision number, so `expected_revision` is refused. `tracker_search_issues`
also takes JQL in `native_query`, always limited to the tracker's own project.

---

## Self-hosted: the Atlassian app

Without an app, a self-hosted deployment offers only the service-account
connection. To offer the Atlassian-account one, the operator registers one
OAuth 2.0 (3LO) app for the whole deployment at
[developer.atlassian.com](https://developer.atlassian.com/console/myapps/):

1. **Authorization → OAuth 2.0 (3LO)**, callback URL
   `https://<your domain>/integrations/jira/oauth/callback`.
2. **Permissions**: add the Jira API with the scopes listed above plus
   `manage:jira-webhook`, and the Jira Software granular scopes.
3. **Distribution**: enable sharing. Jira delivers a private app's webhooks only
   for the app owner's own sites.
4. Set `JIRA_OAUTH_CLIENT_ID` and `JIRA_OAUTH_CLIENT_SECRET`. Set
   `JIRA_WEBHOOK_BASE_URL` only when the deployment's domain is not reachable
   from Atlassian (a tunnel in development); a loopback or private host
   registers no webhooks.

Use one app per deployment: Atlassian allows one webhook URL per app, and
Flow removes webhooks its app registered that no connection holds.

## When something is wrong

- **Test connection** on the row re-reads the site and the projects.
- A connection in error that says to reconnect lost its authorization —
  typically a 3LO grant revoked at Atlassian, or a service-account credential
  rotated. Connect again; the trackers stay.
- Atlassian retires a 3LO grant unused for 90 days. Flow renews idle grants
  monthly, so this only happens while the deployment is down.
