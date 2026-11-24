# Project Home & Settings

## Overview

**Overview** is the project's front page and the fastest answer to "what is
this project doing, and how much agent work went into it?"

- **KPI cards** — sessions launched, tokens used, session time, workflows and
  board tasks, with the tokens and time each session averages once sessions
  have run.
- **Workflow Runs** — a donut of run outcomes with a success rate, total, and a
  legend; failures that need a look are called out rather than buried.
- **Board Task Distribution** — how many cards sit in each column, as a bar
  list. A long bar on one column is usually a queue, not progress.
- **Recent Activity** — the latest things people and agents did in this
  project, newest first.

Two blocks link onward: **Open Runs** on Workflow Runs opens the project's list
of workflow runs, and **Open board** on Board Task Distribution opens the board.

## Settings

**Settings** holds the few project-level things that are not resources.

- **Project name** and **description** — Save stays disabled until you actually
  change something, and a *Saved* chip confirms the write.
- **Artifacts Language** — the language agents write their output in. New
  projects default to English.
- **Reserved workers** — how many sessions this project can always run at once,
  one per worker, with nothing else allowed to occupy them. Left empty, the
  project shares the company's unreserved workers. Only a company admin can
  change it, and not during the free trial, which runs one worker.
- **Owner** — the project's owner, with **Transfer** for the owner or a company
  admin.
- **Danger Zone** — **Archive** takes a finished project out of the way but
  keeps its history; **Delete** removes it. Both ask for confirmation first,
  and both return you to the projects list when they succeed.

> warning Delete is not archive. If you only want the project out of the daily
> list, archive it — an archived project keeps its board, runs, and numbers.

Whether you see the delete control at all depends on your role; see
[Team & access](/docs/people-and-access).
