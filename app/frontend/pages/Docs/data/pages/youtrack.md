# Connecting YouTrack

YouTrack connects per Flow project. A connection names one YouTrack instance —
YouTrack Cloud or a self-hosted server — and the YouTrack projects chosen in
it, and each of those projects becomes a **tracker** on the project's
**Trackers** page. From then on:

- tracker triggers start workflows when an issue is created, moves to another
  state, is assigned, or gets a comment;
- agents read and change issues with the `tracker_*` tools — search, create,
  update, move, assign, comment — and only in the projects chosen.

YouTrack connects through **Aixle Flow**, our app on JetBrains Marketplace. A
YouTrack administrator installs it once; after that, connecting takes one
confirmation in YouTrack, and nobody copies a token or a webhook URL. The app
needs **YouTrack 2026.2 or later**.

---

## Install the Aixle Flow app

A YouTrack administrator (it takes the *Low-level Admin Write* permission):

1. **Administration → Apps → Add app → Browse JetBrains Marketplace**.
2. Find **Aixle Flow** and install it.

The app talks to `https://flow.aixle.com`. A staging or self-hosted Flow sets
its own address in the app's settings (**Administration → Apps → Aixle Flow →
Settings → Aixle Flow URL**).

## Connect

Start from either side; both end in the same place.

**From Flow.** On the project's **Trackers** (or **Integrations**) page choose
**Connect → YouTrack**, enter the instance URL (`https://acme.youtrack.cloud`,
or your server's URL with its path, such as
`https://tracker.example.com/youtrack`) and select **Continue in YouTrack**. In
YouTrack the Aixle Flow page shows which Flow company and project the
connection is for — check it — then tick the YouTrack projects and select
**Approve**.

**From YouTrack.** **Administration → Integrations › Aixle Flow → Connect**.
The page shows a code and opens Flow's connect page: sign in, type the code,
choose the Flow project, and approve. Back in YouTrack, tick the projects and
select **Approve**.

After **Approve** the app does the rest by itself, as the administrator who
approved:

- it creates the service user **Aixle Flow** (`aixle-flow`) — no password, so
  nobody can sign in as it — or reuses it when it already exists;
- it adds the service user to the chosen projects' teams and attaches the app
  to them;
- it creates a permanent token for the service user and hands it to Flow, which
  checks it against your instance before saving anything;
- it saves, for each project, where to send its events.

Then it returns you to the project's Trackers page in Flow.

The service user may take a license seat. YouTrack sends it the notifications
of whatever it is assigned to or watches; turn those off in its profile if
nobody reads them.

### Changing the projects

Connect again — from either side — and tick the whole set of projects the
connection should cover. Projects left out are detached in Flow; their
triggers stop. The trackers, triggers and history of the projects you keep are
untouched.

### What Flow believes from an event

The app sends each project's events with that project's own secret, and Flow
still treats an event as a notification and checks everything with YouTrack
before anything fires:

- the issue is re-read through the API;
- the issue must be in the project the event's address belongs to;
- a state or assignee change counts only when the issue's history (or its
  current value) shows it;
- a comment's text and author are read from YouTrack; comment text never
  travels in an event;
- an "issue created" or comment older than a day is not news, and fires nothing.

Renaming a project in YouTrack (its short name) changes nothing here: Flow
picks up the new short name the next time it reads one of the project's issues.

The row says *"No event yet from …"* until the first event from a project
arrives.

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

The tools act as the **Aixle Flow** service user, so what it may do in a
project is what its team role allows. Its changes are Flow's own: triggers set
to ignore changes Aixle made skip them, and a comment that mentions
`@aixle-flow` matches a trigger's "mentions Aixle" condition.

- **Issue references** — a readable id such as `APP-123`, the issue's database
  id (`2-17`), or its URL on this instance.
- **Issue type** — a value of the project's **Type** field; `tracker_describe`
  lists them. Left out, YouTrack's default applies.
- **Labels** — YouTrack tags, by name, among the tags the service user can see.
  A name YouTrack does not have is refused, and the error lists the tags there
  are; Flow does not create tags. YouTrack lets the service user add a tag only
  when the tag's sharing settings allow **Aixle Flow** (or everyone) to add it
  to issues, whatever its role in the project.
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

Flow calls the instance URL, so it guards it:

- only `https`, with the certificate verified;
- no redirects — use the instance's final URL, path included;
- a host that resolves to a private or internal address is refused, unless the
  operator lists it in `YOUTRACK_TRUSTED_HOSTS` (comma-separated);
- answers are bounded in size and time.

The app's events come from your YouTrack server, so it has to reach Flow's
webhook address. Operators whose Flow domain is not reachable from YouTrack set
`YOUTRACK_WEBHOOK_BASE_URL` to a host that is: it is the base of the event
addresses Flow hands to the app.

## When something is wrong

- **Test connection** on the row re-reads the service user and the projects.
- *"YouTrack rejected the Aixle Flow app's token"* — the token was revoked, or
  the service user banned or deleted. Connect again from either side; the
  trackers stay.
- *"This connection can no longer see …"* — the service user left a project's
  team. Connect again with that project ticked, or leave it out.
- *"YouTrack redirected the request"* — the URL is not the instance's final one
  (http → https, or a missing `/youtrack` path).
- Triggers never fire — check that the Aixle Flow app is attached to the
  project in YouTrack (**Project settings → Apps**) and that the project was
  ticked when you connected.
- The YouTrack page says the pairing expired — a pairing lasts 15 minutes.
  Start Connect again.
