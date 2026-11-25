# Sessions & Runs

One sidebar item, one list. A **run** is one execution of a workflow; a
**session** is one agent working. A run is made of the workflow's sessions, and
a session can also stand on its own, with no workflow behind it.

## The list

Three tabs:

- **All** — everything, and both create actions: **New Session** and
  **Run workflow**.
- **Standalone** — sessions started by hand. Only **New Session** here.
- **Workflow runs** — runs. Only **Run workflow** here.

Filter by agent, status, type, workflow, board task, the person who started
it, or the days it started on, or search by name. Click the **Tokens**, **Cost**,
**Duration** or **Started** header to sort by that column — most expensive or
longest first; click again to flip it. A run sorts by what its sessions add
up to.
A session from a workflow links back to the run it belongs to; a standalone
session has nothing to expand. A run that a
[team](/docs/project-teams) handed out names both:
*Planner → Anna*. A run started for a board task names the task — *#12 Fix
the login redirect* — and links to it, here and in the run's header.

Sessions someone kept private show as locked. You can see that they exist and
what they cost; you cannot read them.

## Starting a session by hand

**New Session** asks for a name and an agent runtime — the Start control stays
disabled until you pick one you actually have a credential for — and drops you
straight into the session it creates. Finished a session and want another like
it? A finished session offers to start a fresh one from the same setup.

## Suspending and restoring a session

An interactive session you started by hand, an Aixle Builder session included,
can be **suspended** instead of finished. Its container stops, and what it was
working on is kept for 30 days:

- the files under `/workspace`, apart from the repositories, the assets the
  session was given, and rebuildable folders such as `node_modules`;
- each repository's branch, its commits that were not pushed, its uncommitted
  changes and its untracked files;
- the agent's conversation.

A session is suspended in two ways:

- **Suspend** next to **Finish session**, when you want to come back to it
  later;
- **the 23-hour limit** an interactive session runs for, which used to finish it.
  An hour before the limit the session warns you.

You get an email when a session is suspended, and again three days before its 30
days are up. A suspended session holds no slot and costs nothing while it waits.

**Restore**, on the session page or on its row in the list, starts a new session
with the same agent, model and resources. It puts the files and the
repositories' work back, and the agent picks up the same conversation. The new
session's page says what it continues and anything that could not be put back.
A resource that has been archived since is left out. Work the agent could not
reapply is left in `/workspace/.aixle-restore`.

**What is not kept:** running processes (a dev server, a watcher), and anything
outside `/workspace` — packages installed globally, caches, `/tmp`. The agent is
told so and installs what it needs again.

After 30 days the saved files are deleted and the session is finished. Anything
the agent had put in `outputs` becomes an asset of the session, as when a session
finishes.

**An interactive workflow step** is suspended the same way, and its run waits for
it: the next steps do not start. The run page shows the step as *Suspended* with the
days left, and whoever the step's session belongs to can **Restore** it there. The
restored session continues the same step, and when it finishes the run carries on.
A step can be suspended and restored more than once; its session page links each
session to the one before. **Skip** moves the run on without it. A suspended step
that is not restored in time fails, and the run goes on as the step's *On failure*
setting says. A run waits for a suspended step for at most as long as the run itself
may last, so a step suspended late in a long run has a shorter window.

## Watching a run

Open a run and you get one card per session, in run order, with the run's
status, id, and totals in the header.

- A **running session shows its terminal live**, embedded in the page. Before
  the container is ready it reads *Session starting…*, then *Connecting to
  terminal…*, then you are watching the agent work. When the session ends it
  reads *Session finishing…* until the run moves on. Someone else's session
  reads *Live view is private* when its owner has turned off *Show my active
  sessions* in their profile.
- A **parallel run shows every active session at once**, each with its own
  console and its own action bar.
- **Only the person who started a session can type into it.** Everyone else it
  is shared with — colleagues on the project, and every session of a run
  someone else started — watches a read-only terminal, and the editor is not
  offered to them: the container holds its owner's agent login and repository
  access.
- Expand a session card for its prompt, its steps, and the note it left
  behind. A failed session shows its error there, and the header names
  *where* the run stopped rather than when it started.

## Steering a run

| Action | When |
| --- | --- |
| **Approve & continue** | A session is waiting for a person, because **Auto-run available** is off on it |
| **Retry** | A session failed, or is waiting on input and should have another go |
| **Skip** | A session should not run. You are asked for a reason, which stays on the record |
| **Cancel run** | The whole run should stop. Offered only while it is still active |

If a run stopped because the workspace hit a usage limit, the run says so in a
banner and offers to run it again once there is room.

## What a run leaves behind

The **Assets** tab of a run lists the files the agents produced, with download
and **promote** controls — promoting lifts a file out of the run and into the
project's [Assets](/docs/assets), where the rest of the team can find it.

A finished session with files waiting for review shows an **Outputs** panel on
its page, with **Review outputs**: tick what to keep and **Save selected**, or
**Dismiss all** if the session produced nothing worth keeping.

Every run keeps its status, log, artifacts, tokens, and cost — including the
runs that failed. That record is what [Analytics](/docs/analytics) counts.
