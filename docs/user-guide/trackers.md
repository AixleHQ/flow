# Trackers

A **tracker** is a Flow project's link to one external project in a task
tracker — an Azure Boards project, a Jira project, a GitHub project or a Linear
team — through a connection made on the project's **Integrations** page. The connection holds the credentials;
the tracker is what agents and triggers address. Through it:

- tracker triggers start workflows when an issue is created, moves to a column,
  is assigned, or gets a comment;
- agents read and change issues with the `tracker_*` tools.

Both work the same way for every provider. Connecting is per provider: see
[Azure DevOps](/docs/azure-devops), [Jira](/docs/jira),
[GitHub](/docs/github#github-projects-as-a-tracker) and [Linear](/docs/linear).

---

## The Trackers page

Open **Trackers** in the project's sidebar, under **Resources**. Each row shows:

| Column | Shows |
| --- | --- |
| **Tracker** | The external project's name, a **Primary** and a **Read-only** badge where they apply, and the handle underneath |
| **Connection** | The connection it goes through, and the provider: **Azure Boards**, **Jira**, **GitHub Projects** or **Linear** |
| **Triggers** | The tracker triggers that listen to it — those set to any tracker appear on every row — each with its workflow, what it waits for and whether it is off. The workflow name opens its **Triggers** tab |
| **Status** | **Active**, **Connection inactive** or **Detached** |

Viewers see the list but no actions.

### Where trackers come from

You normally do not add trackers by hand. Connecting Azure DevOps, Jira or
Linear — or picking projects with **GitHub Projects** on a GitHub connection —
creates one tracker for each external project the connection covers, and the
project's first tracker becomes its primary. A Jira, Linear or GitHub
connection whose projects (Linear: teams) change gets trackers for the new
ones, and the trackers of those it no longer covers are detached.

To get a tracker for another external project, add the project to its
connection on the **Integrations** page; when there is nothing to add here, the
page says so and links there.

**Add tracker** appears only when one of this project's connections covers an
external project that has no row here yet. Connecting creates a tracker for
every external project the connection covers, so this is rare. It asks for the
**Connection**, the **Project**, a **Handle**, and whether it is **Read-only**
or the **Primary tracker**. A tracker added while the project has no primary
becomes the primary.

### Handle

The handle is what agents and triggers call a tracker: an agent passes it as
`tracker`, and the trigger form lists trackers as `Name (handle)`. It is
lowercase letters, digits and dashes, unique in the project, and derived from
the external project's name unless you type one. **Edit handle** (the pencil on
the row) changes it. Triggers point at the tracker, not at its handle, so they
are not affected; workflow instructions that name the old handle need the new
one.

### Primary

The primary tracker is where an agent's call goes when it names no tracker and
nothing else decides — most often, where new issues are filed. A project has at
most one. **Make primary** on another row moves it. Detaching the primary
leaves the project without one until you choose another.

### Read-only

**Make read-only** stops agents changing issues in that tracker: creating,
updating, moving, assigning and commenting are refused, in Flow rather than by
a prompt. Reads still work, and the tracker still starts workflows — but those
runs cannot move the issue on, and no failure comment is posted to it.
**Allow writes** undoes it.

### Usable, and the status badges

A tracker is **usable** when it is not detached and its connection is active.

- **Active** — usable.
- **Connection inactive** — the connection needs attention on the
  **Integrations** page (Test connection, or connect again). Until then agents
  cannot reach the tracker, its events start nothing, and
  **Connect a board column** is not offered.
- **Detached** — detached by hand, or by a Jira, Linear or GitHub connection
  that no longer covers the project.

### Detach and attach again

**Detach** removes the tracker from the project's reach without touching the
connection or the tracker itself:

- agents stop reaching its issues; in a run that tracker started, the
  `tracker_*` tools return an error instead of falling back to another tracker;
- its triggers stay, still switched on, but stop firing. The workflow's
  Triggers tab shows them as listening to "*handle* (detached, not firing)".
  They stay editable: the trigger form keeps the detached tracker and says the
  trigger does not fire. A trigger cannot be moved onto a detached tracker;
- links from board tasks to its issues stay.

**Attach again** on the row brings it back, and its triggers fire again. When
the connection no longer covers the external project — a Jira project taken
off the connection, for example — attaching is refused with that reason: add
the project to the connection on the **Integrations** page first. Reconnecting
does not bring back a tracker you detached.

Removing the connection itself removes its trackers. Their triggers are
switched off first, and from then on show as listening to any tracker.

---

## Connect a board column

The lightest way to let a tracker start work: add one column such as
"Ready for AI" to the tracker's board, and moving an issue there starts a
workflow on a board task linked to the issue. Nothing else on the board has to
change.

The shortcut is the columns icon in a tracker's row, tooltip
**Connect a board column**. It needs:

- permission to change the project;
- a usable tracker;
- a board in the Flow project with at least one column, and at least one
  workflow.

Without a board or a workflow, the icon is greyed out and its tooltip says what
is missing: "Add a board to this project first: the issue gets a task in one of
its columns", or "Create a workflow first: moving an issue to the column starts
it". Create the board (**Tasks → Create your task board**) or the workflow
(**Workflows**), then come back. If the project is not meant to have a board, add a tracker
trigger from the workflow instead (below): without a board its subject is
**None — project-level run**, and the subjects that create a task are greyed
out.

### The drawer

| Field | What to choose |
| --- | --- |
| **Start a workflow when** | **An issue moves to a column**, or **Aixle is mentioned in a comment** — greyed out, with the reason, while Flow cannot recognise a mention (below) |
| **Column** | The column on the tracker's board, picked from its columns. Only when Flow cannot read them do you type the name, and the drawer warns that it is not checked: it must match the board exactly, including case |
| **Workflow** | The workflow to start |
| **Task column** | Where the issue's board task is created, the first time |

Then select **Connect**. Every step of the workflow must allow auto-run: the
trigger fires with nobody at the keyboard, so otherwise Connect fails and names
the steps to change.

### What it creates

An ordinary tracker trigger on the chosen workflow:

- **An issue moves to a column**: the `tracker.issue.status_changed` event,
  filtered to the column you named (`change.to.name`);
- **Aixle is mentioned in a comment**: the `tracker.comment.created` event,
  filtered to comments that mention Flow (`comment.mentions_me`);
- this tracker only;
- subject `find_or_create_task`: the issue's board task, created in the
  **Task column** the first time;
- changes made by Aixle ignored (`aixle_changes: ignore`).

The trigger runs as you. It appears on the workflow's **Triggers** tab as
"Issue moves to Ready for AI" or "Aixle is mentioned in a comment", where you
edit, switch off or delete it like any other trigger. Connecting the same
column to the same workflow again is refused, since the workflow already has
that trigger; connecting it to another workflow adds a trigger there, and both
workflows start.

Flow never moves the issue because a run started or finished. Say in the
workflow's instructions where the issue goes next — "In Progress" when work
starts, "Review" when it is done — and the agent moves it with
`tracker_transition_issue`. Those moves do not start the same trigger again.

A mention is recognised only once Flow knows its own account in the tracker:

- **Azure Boards** — after the connection has created, updated, moved or
  assigned a work item at least once;
- **Jira** — a service-account connection, or an Atlassian account marked
  **This Atlassian account is kept for Aixle**;
- **GitHub Projects** — always: the connection writes as the app, and people
  mention it as `@<app-slug>`;
- **Linear** — an API-key connection marked
  **This Linear account is kept for Aixle**. Aixle's Linear app is its own
  account too, but Linear does not let people mention or assign it, so with the
  app only state moves and new issues start work.

Until then, a mention trigger never fires: the drawer greys out
**Aixle is mentioned in a comment** and says why, and the trigger form says so
under **Only when Aixle is mentioned**.

---

## Tracker triggers

The shortcut is one case of a tracker trigger. For anything else, open the
workflow, go to **Triggers**, select **Add trigger**, and choose the trigger
type **Task tracker event**. It is offered once the project has a tracker that
is not detached. The general model — who a trigger runs as, and subjects — is
in [Triggers and gates](/docs/triggers-and-gates).

### Events

| **When** | Event | Fires when |
| --- | --- | --- |
| **Issue moves to a status (column)** | `tracker.issue.status_changed` | The issue moves to another column of the tracker's board |
| **Issue is created** | `tracker.issue.created` | An issue is created in the tracker's project |
| **Issue is assigned** | `tracker.issue.assigned` | The issue's assignee changes, including when it is cleared — on GitHub Projects and Linear only when someone is assigned |
| **Comment is added** | `tracker.comment.created` | A comment is added to the issue |

A status is a column of the tracker's board where there is one, not the
workflow state behind it; how each provider maps the two is on its page. The
event cannot be changed once the trigger exists.

### The form

- **Tracker** — one tracker, or **Any tracker in this project**. Any tracker
  keeps the trigger working while a project moves from one tracker to another.
  A trigger whose tracker was detached keeps it, marked detached.
- **Moves to** — for status changes: one or more columns. Blank fires on any
  status change. Names match exactly, including case.
- **Only when Aixle is mentioned** — for comments. On by default; the mention
  rules are the same as for the shortcut, and the form says when a mention
  cannot start the trigger yet.
- **Text contains** — for issue events, the issue's title and description; for
  comments, the comment. Case-sensitive.
- **Changes made by Aixle** — see below.
- **Subject (what the run is about)**, **Task column**, **Task title template**
  — see below.
- **Comment on the issue when a run fails** — on by default; see
  [When a run fails](#when-a-run-fails).

There is no assignee condition: an **Issue is assigned** trigger fires on every
assignee change in the trackers it listens to. The API and the personal MCP tool
`create_workflow_trigger` accept any filter over the event data —
`issue.type`, `issue.labels` (with the `includes` operator),
`change.to.category`, `change.to` for an assignee. The form lists such
conditions under **Other conditions** and keeps them when you save.

A workflow takes a tracker trigger once: a second one with the same event,
tracker and conditions is refused, because the two would start the workflow
twice for every event.

### The board task

| **Subject** | The run is about |
| --- | --- |
| **The issue's task — create it the first time** (default in a project with a board) | The board task linked to the issue; if there is none, a new one in the **Task column**, linked to it |
| **The issue's task, if it has one** | The linked task, or no task at all |
| **A new task every time** | A new linked task in the **Task column**, each time |
| **None — project-level run** (default in a project without a board) | No task |

A new task is titled `{{issue.key}} {{issue.title}}` unless you give a
**Task title template**, and its description links the issue and carries its
title and description, cut at 500 characters. Putting the task in the
**Task column** does not start a workflow bound to that column. An existing
task stays where it is.

The issue's task is the active (not archived) one linked to the issue in this
project. A link made by the trigger's own workflow wins. When the issue is
linked to several tasks and none of the links came from this workflow, none is
chosen, so the default subject creates a new one. A task shows its issues under **Tracker issues** in its details.

The run is told which tracker and issue started it and what changed, including
the comment's text, and its `tracker_*` tools act on that tracker by default.

### Changes made by Aixle

An agent's change comes back from the tracker as an event like anyone's. Flow
records every change its tools make, matches a returning event to a write made
in the ten minutes before it, and so to the run that made it, and lets each
trigger decide:

| **Changes made by Aixle** | Fires on an event Aixle caused |
| --- | --- |
| **Ignore them** (default) | Never |
| **Only from other workflows** | Unless this trigger's workflow is already in the chain of workflows that led to the change. One workflow hands an issue to the next, and nothing starts itself again |
| **Always (up to the chain limits)** | Always, including its own workflow — for a deliberate walk through statuses, one run at a time |

A change counts as Aixle's when it is matched to a run, or when it was made by
the connection's own account (someone using that account by hand, for
example). A person's change starts a fresh chain. On a Jira connection that
acts as a person who did not mark the account as kept for Aixle, only the
matched changes count, so that person's own edits still start triggers set to
ignore Aixle.

The tracker may send the event before it has answered the write. Flow records
which issue a write is about before sending it, so the event is still matched.
A new issue is known only from the tracker's answer, so an **Issue is created**
event waits, for up to about a minute, while an agent's create in the same
tracker project is still unanswered.

Two limits apply whatever the triggers say:

- **Chain depth** — counting the run a person's change started as the first,
  the change made by the fifth run in a chain starts nothing.
- **Per-issue budget** — after ten Aixle-caused events on one issue in an
  hour, Aixle's further changes to it start nothing until the hour rolls on.

People's changes are never limited. A dropped event is logged, not shown in
the UI.

### Delivery

Events reach Flow from the tracker itself, so a trigger fires only while
delivery works:

- **Azure Boards** — `workitem.created`, `workitem.updated` and
  `workitem.commented` Service Hooks, created for the connection's Azure
  projects the first time a tracker trigger is created or switched on.
  **Test connection** on the **Integrations** page checks them with Azure,
  recreates any that are missing or were refused, and names the ones Azure
  still refuses. See [Service Hooks](/docs/azure-devops#service-hooks).
- **Jira** — a webhook Flow registers for an Atlassian-account connection, or
  one a Jira admin adds for a service-account connection. See
  [The webhook](/docs/jira#the-webhook).
- **GitHub Projects** — the GitHub App's own webhook, once the app has the
  Projects and Issues permissions and their events. See
  [GitHub Projects as a tracker](/docs/github#github-projects-as-a-tracker).
- **Linear** — the webhook of Aixle's Linear app, or for an API-key connection
  one webhook per team, which only a workspace admin's key can register. See
  [The webhooks](/docs/linear#the-webhooks).

Either way the tracker has to reach the deployment's domain. With a loopback
or private host, Flow creates no Service Hooks and registers no Jira or Linear
webhooks.

Before matching, Flow reads the issue again from the tracker, so the `issue`
fields a filter sees are its current state. A redelivered event is
processed once; two connections to the same external project in one Flow
project start a trigger once; and each trigger starts at most one run per
event.

Delivery is best effort. Flow does not poll, and an event that never arrives
is not replayed later. The tools do not depend on delivery.

### When a run fails

When a run a tracker event started fails or is cancelled, Flow posts one
comment on the issue — the only write the platform makes on its own: which
workflow failed, the failed step and its error, and a link to the run. Nothing
is posted to a read-only tracker. The comment counts as a change made by
Aixle. It is on by default; turn off **Comment on the issue when a run fails**
on the trigger form (`notify_on_failure: false` through the API) to stop it.

---

## Tools

The `tracker_*` tools are listed in the tool picker under **Task trackers**
once the project has a usable tracker. Attach them to a workflow or a step like
any other tool ([Tools](/docs/tools)). A run a tracker event started has all of
them without attaching anything.

| Tool | Does |
| --- | --- |
| `tracker_list` | Lists the project's trackers: handle, provider, primary, access, whether each is usable, and which one started this run |
| `tracker_describe` | A tracker's statuses with a portable category (todo, in_progress, done, canceled), its issue types and the extra fields that can be set |
| `tracker_search_issues` | Searches issues by text, status, type, assignee, labels or ids, paginated; Jira also takes JQL in `native_query`, and GitHub Projects its project filter syntax |
| `tracker_get_issue` | Reads one issue in full, by id, key or URL |
| `tracker_list_comments` | Lists an issue's comments, paginated |
| `tracker_list_users` | Finds people an issue can be assigned to; not every tracker can list users |
| `tracker_create_issue` | Files an issue, and links it to the run's board task unless `link_to_task` is false |
| `tracker_update_issue` | Changes title, description, labels or extra fields; on Azure Boards, `expected_revision` refuses the edit if the issue changed meanwhile |
| `tracker_transition_issue` | Moves an issue to another status |
| `tracker_assign_issue` | Sets an issue's assignee |
| `tracker_add_comment` | Comments on an issue |
| `tracker_link_task` | Links a board task to an issue; changes nothing in the tracker |

What a status or an assignee is differs by provider. On Azure Boards,
`tracker_transition_issue` takes a state and the card moves to the column that
state maps to, and assignees are emails or display names. On Jira it takes a
column, a workflow status or a transition name. On GitHub Projects it takes a
Status option and assignees are GitHub logins; on Linear it takes a workflow
state, and assignees are names, usernames or emails of the team's members. The
provider pages have the rest.

### Which tracker a call acts on

Every tool takes an optional `tracker`. The tracker is chosen in this order:

1. The `tracker` the call names — a handle or an id.
2. The tracker that started the run. If it is no longer usable, the call fails
   rather than going to another tracker.
3. For tools that take an issue, the one tracker the issue's reference belongs
   to: a Jira or Linear key such as `APP-12`, a GitHub `owner/repo#12`, or the
   issue's URL. A GitHub reference names only the organization, so it decides
   only when the project has one tracker on that organization.
4. The primary tracker; when no usable tracker is primary, the only usable one.
5. Otherwise the call fails and names the handles to choose from.

A detached tracker is never chosen. A write to a read-only tracker is refused,
and the error names the primary tracker when that is a different one.

### Who a write is attributed to

In the tracker, a change is made by whoever the connection acts as — see
[What the connection runs as](/docs/azure-devops#what-the-connection-runs-as)
for Azure DevOps, and the tables at the top of [Jira](/docs/jira) and
[Linear](/docs/linear). On GitHub Projects it is the app, as `<app-slug>[bot]`. In Flow, every
write is recorded before it is sent, with the session, run and workflow that
made it. That record is how "Changes made by Aixle" knows which run caused an
event, and it makes retries safe:

- the same call repeated in one session, or with the same `operation_key`,
  returns the first result instead of writing twice;
- a write whose outcome Flow could not confirm is reported as
  `outcome_unknown` — read the issue before trying again.

---

## Connecting

- [Azure DevOps](/docs/azure-devops) — the organization, the Azure projects,
  and the Service Hooks.
- [Jira](/docs/jira) — an Atlassian account or a service account, the webhook,
  and board columns as statuses.
  What Aixle keeps about Jira accounts, and when it erases it, is under
  [Personal data](/docs/jira#personal-data).
- [GitHub](/docs/github#github-projects-as-a-tracker) — organization projects
  on the GitHub App connection, the permissions the app needs, and the Status
  field as the board's columns.
- [Linear](/docs/linear) — Aixle's Linear app or an API key, the per-team
  webhooks, and workflow states as statuses.
