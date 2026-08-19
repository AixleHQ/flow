# Sessions & Runs

One sidebar item, one list. A **run** is one execution of a workflow; a
**session** is one agent working. Every step of a run is a session, and a
session can also stand on its own, with no workflow behind it.

## The list

Three tabs:

- **All** — everything, and both create actions: **New Session** and
  **Run workflow**.
- **Standalone** — sessions started by hand. Only **New Session** here.
- **Workflow runs** — runs. Only **Run workflow** here.

Filter by agent, status, type, or the person who started it, or search by name.
A workflow-step session links back to the run it belongs to; a standalone
session has nothing to expand.

Sessions someone kept private show as locked. You can see that they exist and
what they cost; you cannot read them.

## Starting a session by hand

**New Session** asks for a name and an agent runtime — the Start control stays
disabled until you pick one you actually have a credential for — and drops you
straight into the session it creates. Finished a session and want another like
it? A finished session offers to start a fresh one from the same setup.

## Watching a run

Open a run and you get one card per step, in run order, with the run's status,
id, and totals in the header.

- A **running step shows its terminal live**, embedded in the page. Before the
  container is ready it reads *Session starting…*, then *Connecting to
  terminal…*, then you are watching the agent work.
- A **parallel run shows every active step at once**, each with its own console
  and its own action bar.
- Expand a step card for its prompt, its sub-steps, and the note it left
  behind. A failed step shows its error there, and the header names *where* the
  run stopped rather than when it started.

## Steering a run

| Action | When |
| --- | --- |
| **Approve & continue** | A step is waiting for a person. This is the approval you set on the step |
| **Retry** | A step failed, or is waiting on input and should have another go |
| **Skip** | A step should not run. You are asked for a reason, which stays on the record |
| **Cancel run** | The whole run should stop. Offered only while it is still active |

If a run stopped because the workspace hit a usage limit, the run says so in a
banner and offers to run it again once there is room.

## What a run leaves behind

The **Assets** tab of a run lists the files the agents produced, with download
and **promote** controls — promoting lifts a file out of the run and into the
project's [Assets](/docs/assets), where the rest of the team can find it.

Back in the list, a run with unreviewed output offers **Review outputs**: tick
what to keep and **Save selected**, or **Dismiss all** if the run produced
nothing worth keeping.

Every run keeps its status, log, artifacts, tokens, and cost — including the
runs that failed. That record is what [Analytics](/docs/analytics) counts.
