# GitLab as a tracker, connected through a service account

Status: **Agreed and built 2026-10-20 on `artempartos/tracker-asset-sync-design`; not checked on a live
GitLab yet.**
Related: [`task-tracker-integrations.md`](./task-tracker-integrations.md) (the tracker port),
[`tracker-attachments.md`](./tracker-attachments.md) (files), `docs/user-guide/gitlab.md` (the code host as
built).

## 1. Goal

GitLab today is a code host only: repositories, merge requests and CI gates, connected with a personal
access token (`api` scope). This change makes GitLab issues a **tracker**, like Jira or Linear, over the same
connection. It also replaces the pasted token with a **service account** that Flow creates itself, after a
one-time OAuth consent.

## 2. Decisions (agreed 2026-10-20)

| # | Question | Decision |
|---|---|---|
| 1 | What is a column? | **The label lists of one board the person picks, plus Open and Closed.** This works on every tier. Moving a card adds the target list's label, removes the other lists' labels, and closes or reopens the issue for Closed. GitLab's work item Status (Premium, 18.4+, GraphQL only) is left for later, behind a per-tracker switch |
| 2 | How does Flow authenticate? | **OAuth once, then a service account.** A group Owner signs in through the deployment's GitLab OAuth app (`api` scope, PKCE). With that token, Flow creates a service account in the chosen group, makes it a Maintainer, and mints its token. Flow then keeps only the service account's token, and the person's token is dropped. The pasted personal access token stays available |
| 3 | Code host too? | **Yes, one connection.** The service account's token is stored where the personal access token was (`credentials_data.personal_access_token`). Repositories, merge requests, CI gates and clones work through it unchanged, and they act as the bot |

## 3. Facts that shaped it (checked 2026-10-20)

- **No app model.** GitLab has no installable app comparable to a GitHub App, and its OAuth has no
  `client_credentials` grant. A deployment-wide OAuth app acts as the person who consented.
- **Service accounts.** Available on every tier since 18.11, with the
  `service_accounts_available_on_free_or_unlicensed` flag removed at GA. On GitLab.com, Free allows up to
  100 per top-level group.
  - Created by an Owner of the group, or by a project Maintainer for a project account.
  - They take no seat.
  - A token has no expiry unless the group requires one; otherwise it lasts up to 365 days.
  - Source: <https://docs.gitlab.com/user/profile/service_accounts/>
- **Uploads.**
  - `POST /projects/:id/uploads` returns Markdown for the file.
  - `GET /projects/:id/uploads/:secret/:filename` downloads one (17.4+, Guest and above).
  - An issue has no attachment list: files are `/uploads/<32 hex>/<name>` links in its description and
    notes.
  - Source: <https://docs.gitlab.com/api/project_markdown_uploads/>
- **Webhooks.**
  - Project hooks work on every tier and need Maintainer. They are authenticated by `X-Gitlab-Token`.
  - Group hooks are Premium.
  - An Issue Hook's `changes` carries `labels` with `previous` and `current`. Assignee changes come as
    `changes.assignees`.
  - Confidential issues and their notes arrive only with the `confidential_*` events.
  - Source: <https://docs.gitlab.com/user/project/integrations/webhook_events/>
- **Visibility.** A confidential issue is visible to Planner and above; an internal note to Reporter and
  above. Both are narrower than an Aixle project, so their files are restricted (tracker-attachments §9.3).

## 4. Connecting

```text
Integrations → Connect GitLab → "Connect with GitLab"
  → gitlab.com/oauth/authorize (api, PKCE, signed single-use state)
  → /integrations/gitlab/oauth/callback
      exchange the code; list the groups the person owns (min_access_level=50)
      a pending connection keeps the person's token, encrypted, until a group is picked
  → Integrations page, "Pick the group for Aixle's service account"
      POST /groups/:id/service_accounts             (name "Aixle Flow", username aixle-flow-<hex>)
      POST /groups/:id/members                      (the account, Maintainer)
      POST /groups/:id/service_accounts/:id/personal_access_tokens   (api)
      the person's token is dropped; the connection is active as the bot
```

- **Reconnecting.** Picking the same group again reuses the connection row.
- **Several groups.** One service account per connection, in one group. Projects outside that group are not
  reachable unless the group Owner invites the account there.
- **Token expiry.** When the group requires an expiry, the token's `expires_at` is kept.
  The daily tracker sweep (`Activities::Trackers::RefreshSubscriptionsActivity`, through
  `Gitlab::ServiceAccountToken`) rotates it 30 days before it ends, through
  `POST /personal_access_tokens/self/rotate`. It asks for 365 days, then shorter if the group refuses: a
  rotation without a date gets GitLab's one-week default.
- **Self-managed.** The instance admin registers the OAuth app (Admin → Applications, trusted) and gives the
  operator its id and secret. `GITLAB_ENDPOINT` stays deployment-wide.

## 5. The tracker

- **Scope.** A GitLab project, keyed by its numeric id, with the board picked for it. The "Issue boards"
  picker on the connection's row writes `settings.gitlab_trackers`:
  `[{ id, path, name, board_id, board_name }]`.
- **Statuses.** Open, then the board's label lists in their order, then Closed.
  - An issue's status is Closed when it is closed. Otherwise it is the first list, in board order, whose
    label the issue carries, or Open if it carries none.
  - Categories follow the list name, as on GitHub Projects. Open is `todo` and Closed is `done`.
- **Issues.** An issue is keyed by its global id. Its readable key is `group/project#iid`, and it can also be
  referred to by its URL. `tracker_create_issue` files it in the scope's project.
- **Events.**
  - One project hook per tracked project. It points at the tracker ingress (`/webhooks/trackers/:token`),
    uses the subscription's secret as its `X-Gitlab-Token`, and carries `issues_events` and `note_events`.
  - The confidential events are deliberately not subscribed. A confidential issue's title, or an internal
    note's text, would otherwise reach a trigger's event data and the task it creates, which every member
    of the Aixle project can read. An internal note that arrives anyway is dropped.
  - The hook's own change hints are trusted, as for every subscription authenticated by its own secret.
  - A status change is the label lists and the state, before and after.
- **Files.** Uploads linked from the description and notes.
  - A file on a confidential issue or in an internal note is restricted.
  - Files go up through the uploads API and are shown in a comment.
- **Identity.** The service account: writes are its own, and `@<username>` is a mention.

## 6. Not in this change

- Work item Status columns and group boards.
- GitLab Epics.
- A per-connection GitLab instance URL.
