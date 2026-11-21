# Session queues

Only so many agent sessions can run at once: each of your company's
**workers** runs one. When more are asked for than there are free workers, Flow
**queues** them rather than failing them: a queued session keeps its place,
starts by itself when a worker frees, and never loses the work that was asked of
it.

This page covers how the workers are shared between your projects, how to make
sure the projects that matter most never wait, and what a waiting session is
waiting for.

## What is queued, and what is not

**Queued:** every session. Workflow-step sessions and agent sessions started
inside a project wait in that project's queue.

**Agent logins** have no project, so they queue per person instead: two at a
time, outside the company's workers. Signing in to two runtimes at once starts
both immediately.

**Not queued:** tool executions. Running a tool on its own is not a session and
takes no worker.

## The two numbers

| | set by | what it means |
|---|---|---|
| **Workers** | an administrator, on **Settings → General** | how many sessions all of the company's projects may run at once |
| **Reserved workers** | an administrator, in the project's **Settings** | how many of those workers belong to this one project |

### Projects with no reservation

They share every worker no project has reserved. A worker that frees up goes to
the session that has waited longest, whichever of these projects it belongs to.

Each of them runs at most **4** sessions at once, however many workers the
company has (the deployment can change that default). A company whose work all
sits in one project should reserve workers for it, or the rest can never be
used.

### A project with reserved workers

Its reserved workers are its own. It can always run that many sessions, because
nothing else may occupy them, even while the project sits idle.

The number is also the project's maximum. A project with 3 reserved runs 3 at
most, even when the shared workers are free.

**Clearing the field** gives the reservation back: the project returns to the
shared workers, up to 4 at a time.

## Prioritising projects

Flow does not rank projects against each other, and a session cannot jump the
queue. You set priority through capacity instead: reserve workers for the
projects that must never wait, and let the rest share what is left.

Ten workers across eight projects, two of which must never wait:

```
workers                     10
  reserved   SDLC         4   ← SDLC can always run 4
             Support      2   ← Support can always run 2
  shared                  4   ← the other six projects share these
```

SDLC and Support never wait behind Marketing, and a busy week in Marketing never
slows them down. Marketing, Operations, Accounting and the other projects take
turns on the shared 4, longest-waiting session first.

What this costs you:

- **A reserved worker sits idle when its project does.** Nobody else may borrow
  it, and you pay for it either way.
- **A reserved project cannot burst.** In the example, SDLC runs 4 at most, even
  when nobody is using the shared 4.
- **The shared workers are first come, first served.** None of the projects
  sharing them goes ahead of another.

A board task's **priority** does not change where its session sits in the
queue.

## The budget rule

Reservations come out of the company's workers, so together they can never
exceed it. Saving a number that does not fit is refused, and the message says
what is left:

> 5 exceeds the company's 10 workers. 7 of 10 is already reserved by other
> projects, so this project can be set to at most 3.

A project's settings and the company's settings both show how many workers are
unreserved, and which projects hold the rest.

A project that has no reservation of its own takes none of the budget.
Otherwise eight projects on the default of 4 would need 32 workers before the
first reservation could be saved.

## Who can change what

- **The number of workers:** an administrator, on **Settings → General**. The
  free trial runs one worker, and the number can be changed once a card is
  added.
- **A project's reserved workers:** an administrator, in that project's
  settings. Not during the free trial.
- **A platform admin** can change either in the admin area.

Everyone else sees both numbers but cannot change them.

## What a waiting session looks like

A session that is not running yet tells you which of these it is waiting for:

| Shown | Meaning |
|---|---|
| **Waiting for a free session slot** | Every worker the project may use is busy. Another session has to finish first. |
| **Waiting for cluster capacity** | A worker was granted, but the cluster has nowhere to put the container yet. |
| **Waiting for a free machine** | The project runs on its own [runner](/docs/runners), and every machine of it is busy. |
| **Starting session…** | A worker is granted and the container is coming up. |

Sessions start in the order they were asked for, across all of a company's
projects: a worker that frees up goes to the session that has waited longest,
unless that session's own project is at its limit. Cancelling a queued session
gives its place to the next one immediately.

## Things worth knowing

- **Lowering a number never stops a running session.** It only stops new ones
  from starting until usage falls below it.
- **Raising a number takes effect at once.** Whatever was waiting starts
  immediately; there is nothing to restart and nothing to wait for.
- **Queue time is not run time.** A session that waited an hour for a worker
  does not lose an hour of its own execution budget.
- **A queued step does not make its run look stuck.** A run whose step is
  waiting for a worker reports itself as queued rather than running, and is
  never reaped for being slow.

## For operators

A company's workers are its limit, held in the database. Its administrators set
it on **Settings → General**, and a platform admin on the company's page in the
admin. A company with no limit of its own is unbounded: each project still runs
at most the default, a project's reserved number is only its own cap, and
nothing is metered. Where we host, a paying company cannot be left without a
limit; an internal organisation is left unbilled by ticking **Managed by
Aixle**, which also takes the limit out of its own admins' hands.

There is no deployment-wide ceiling. `SESSION_CONCURRENCY_LIMIT` used to be one
and nothing reads it any more: a single number for the whole installation could
not describe a deployment running several organisations, and it was never the
number a customer was sold.

Lowering a company below the sum of its projects' reservations is possible, and
nothing refuses it — a downgrade must not be blocked by how the capacity was
divided. The company limit is then honoured and the reservations are not, which
the queue health line reports as over-commitment.

Admission is always on and cannot be paused.

The per-project default is `SESSION_PROJECT_CONCURRENCY_DEFAULT`, read live — a
config change applies as each pod restarts, with nothing to run afterwards.

The admin's Session admission page shows the current queues, what is reserved,
and the health counters.
