# Connecting YouTrack

YouTrack connects per Flow project. A connection names one YouTrack instance —
YouTrack Cloud or a self-hosted server — and the YouTrack projects you pick in
it, and each of those projects becomes a **tracker** on the project's
**Trackers** page. From then on:

- tracker triggers start workflows when an issue is created, moves to another
  state, is assigned, or gets a comment;
- agents read and change issues with the `tracker_*` tools — search, create,
  update, move, assign, comment — and only in the projects you picked.

YouTrack connects with a **permanent token**, and Flow acts as the token's
owner. Events reach Flow through JetBrains' **Webhook Triggers** app, which a
project admin sets up once in each YouTrack project. The app needs **YouTrack
2026.2 or later**; on an older server the tools work, but triggers do not fire.

---

## Connect

1. Sign in to YouTrack as the account Flow should act as — best an automation
   account kept for Flow. It may take a license seat, and YouTrack sends it the
   notifications of whatever it is assigned to or watches; turn those off in its
   profile if nobody reads them. Under the profile → **Account Security**,
   create a **permanent token** with the *YouTrack* scope. It does not expire;
   it stops working when it is deleted or its account is banned.
2. The account needs, in each project Flow should reach: read the project, its
   issues, fields, comments and team; create issues; update issues and their
   fields, State and Assignee included; add comments; and use the tags agents
   should set. It needs no administration rights. Give it access only to those
   projects: what the account can see is all a connection can reach.
3. In Flow, on the project's **Integrations** page choose **Connect → YouTrack**,
   enter the instance URL (`https://acme.youtrack.cloud`, or your server's URL
   with its path, such as `https://tracker.example.com/youtrack`) and the token,
   and select **Check**.
4. Pick the projects to connect.
5. Tick **This YouTrack account is kept for Aixle** only when it is: Flow then
   treats that account's changes as its own, and a comment that mentions it as
   `@login` matches a trigger's "mentions Aixle" condition. Leave it off for
   your own token — otherwise your own edits would be ignored by triggers set
   to ignore changes Aixle made.

Connecting again with the same URL replaces the token in place: the trackers,
their webhooks and their triggers stay. If the new token belongs to another
account, Flow says so — mentions and its own changes are recognised by account.

## The Webhook Triggers app

Tracker triggers need YouTrack to send its events. Open **Webhook setup** (the
webhook icon) on the connection's row: it shows, for each connected project, a
URL, a header name and a token. Then, in YouTrack:

1. A YouTrack admin installs **Webhook Triggers** from JetBrains Marketplace
   (**Administration → Apps**), once for the instance.
2. A project admin (it takes the *Update Project* permission) attaches the app
   to the project and opens the project's **Apps → Webhook Triggers** settings.
3. Enter the **token** and the **header name** Flow shows, and add Flow's URL
   to **All Events** — or to *Issue Created*, *Issue Updated* and
   *Comment Added*.
4. Repeat for each connected project: each has its own URL.

The app keeps **one token per YouTrack project**, shared by every URL it posts
to. If the project's app already serves another system and has a token, keep
it: choose **This project's app already has a token** and enter it (and its
header name) in Flow instead.

A delivery belongs to the project whose URL it was sent to. Renaming a project
in YouTrack (its short name) changes nothing here: Flow picks up the new short
name the next time it reads one of the project's issues.

The row says *"No webhook event yet from …"* until the first delivery from a
project arrives; the setup dialog shows when the last one came. YouTrack has to
reach the deployment's domain.

### What Flow believes from a delivery

The shared token is the only thing a delivery carries, so Flow treats it as a
notification and checks everything with YouTrack itself before anything fires:

- the issue is re-read through the API;
- the issue must be in the project the URL belongs to;
- a state or assignee change counts only when the issue's history (or its
  current value) shows it;
- a comment's text and author are read from YouTrack, not from the delivery;
- an "issue created" or comment older than a day is not news, and fires nothing.

---

## Projects and states

A tracker is a YouTrack project. Its statuses are the values of the project's
**State** field (or its state field under another name) — what YouTrack's agile
boards are usually built on. YouTrack only says whether a state is
*resolved*, so the portable category comes from that and the name:

| State | Category |
| --- | --- |
| Unresolved, named like *In Progress*, *In Review*, *Testing*, *Verification* | `in_progress` |
| Any other unresolved state | `todo` |
| Resolved, named like *Won't fix*, *Duplicate*, *Obsolete*, *Can't reproduce* | `canceled` |
| Any other resolved state | `done` |

A trigger's **Status** condition names a state, such as "Ready for AI".
`tracker_transition_issue` takes a state's name or id; a move the project's
workflow rules forbid comes back refused with YouTrack's reason.

## Tools

- **Issue references** — a readable id such as `APP-123`, the issue's database
  id (`2-17`), or its URL on this instance.
- **Issue type** — a value of the project's **Type** field; `tracker_describe`
  lists them. Left out, YouTrack's default applies.
- **Labels** — YouTrack tags, by name, among the tags the account can use. A
  name YouTrack does not have is refused, and the error lists the tags there
  are; Flow does not create tags.
- **People** — by login, full name or email; it must match exactly one person
  the project's **Assignee** field offers. `none` clears it.
  `tracker_list_users` lists them.
- **Extra fields** — any of the project's enum, state, user, version, build,
  owned, string, number or text fields other than State, Type and Assignee, by
  their field name: `{"Priority": "Major"}`. Values are checked against the
  field's own; `tracker_describe` lists the fields.
- **Search** — by text, state, type, assignee, tags or ids; `open_only` keeps
  unresolved issues. `native_query` takes YouTrack's query language
  (`Priority: Critical`, with an optional `sort by:`) and is ANDed after the
  project; an issue outside the tracker's project is dropped whatever it says.
- YouTrack issues have no revision number, so `expected_revision` is refused.

An **Issue is assigned** trigger fires once for each person added to the
assignee field, not when it is cleared.

---

## Self-hosted YouTrack

Flow calls the instance URL you enter, so it guards it:

- only `https`, with the certificate verified;
- no redirects — enter the instance's final URL, path included;
- a host that resolves to a private or internal address is refused, unless the
  operator lists it in `YOUTRACK_TRUSTED_HOSTS` (comma-separated);
- answers are bounded in size and time.

Set `YOUTRACK_WEBHOOK_BASE_URL` only when the deployment's domain is not
reachable from the YouTrack server (a tunnel in development): it is the base of
the URLs the setup dialog shows.

## When something is wrong

- **Test connection** on the row re-reads the account and the projects.
- *"YouTrack rejected the permanent token"* — it was revoked, or its account
  banned or deleted. Create a new token and connect again with the same URL; the
  trackers stay.
- *"This connection can no longer see …"* — the account lost access to a
  project. Give it back in YouTrack, or take the project off the connection.
- *"YouTrack redirected the request"* — the URL is not the instance's final one
  (http → https, or a missing `/youtrack` path).
- Triggers never fire — check the project's Webhook Triggers settings: the URL,
  the header name and the token must match the setup dialog exactly, and the
  events must include the ones the trigger waits for.
