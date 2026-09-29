# Session queues

Only so many agent sessions can run at once. When more are asked for than there
is room for, Flow **queues** them rather than failing them: a queued session
keeps its place, starts by itself when a slot frees, and never loses the work
that was asked of it.

This page is the whole picture — every combination of settings, and what each
one does.

## What is queued, and what is not

**Queued:** every session. Workflow-step sessions and agent sessions started
inside a project wait in that project's queue.

**Agent logins** have no project, so they queue per person instead: two at a
time, outside any company's limit. Signing in to two runtimes at once starts
both immediately.

**Not queued:** tool executions. Running a tool on its own is not a session and
takes no slot.

## The two numbers

| | set by | what it means |
|---|---|---|
| **Project limit** | company admin, in the project's settings | how many sessions this project may run at once |
| **Installation ceiling** | whoever runs the deployment | how many sessions the whole installation may run at once |

Either can be absent. All four combinations are supported, and they behave
differently enough to be worth stating one by one.

### No ceiling, no project limit

Every project may run the installation default — **4** unless the deployment
changed it. Projects do not affect each other, and nothing bounds the total
except the cluster itself.

This is the out-of-the-box shape.

### No ceiling, project limit set

The project may run its own number instead of the default. Still nothing bounds
the total: with no shared ceiling there is no shared capacity, so a project
limit here is simply that project's own cap.

### Ceiling set, no project limit

The project draws on the **shared pool** — the ceiling less every reservation —
and may run at most the default at once. Projects without limits compete for the
shared pool first-come, first-served.

### Ceiling set, project limit set

The project limit becomes a **reservation**. The project can always reach its
number, because nothing else is allowed to occupy it — not even while the
project sits idle. It is capacity you can count on, not a cap you might not get
to use.

## Reservations and the shared pool

An installation with a ceiling of 10, where three projects have reserved 1, 2
and 3:

```
ceiling                    10
  reserved   Alpha  1      ← Alpha can always run 1
             Beta   2      ← Beta can always run 2
             Gamma  3      ← Gamma can always run 3
  shared            4      ← every other project competes for these
```

Every project without a limit of its own shares those 4, each still bounded by
the default. Alpha, Beta and Gamma never compete for them, and nobody can borrow
a reservation that is sitting idle.

**Clearing a project's limit** hands its reservation back to the shared pool.
That is how you move a project off a reservation and onto the shared queue:
empty the field and save.

## The budget rule

Reservations are drawn from the ceiling, so they may never add up to more than
it. Saving a limit that does not fit is refused, and the message says what is
left:

> 5 exceeds the installation limit of 10 concurrent sessions. 7 of 10 is already
> allocated to other projects, so this project can be set to at most 3.

The project's settings also show how much of the ceiling is unreserved, and
which of **your company's** projects hold the rest. Reservations held by other
companies in the same installation are summed into a single line rather than
named.

The same rule is enforced from the other side: the deployment cannot lower the
ceiling below what is already reserved.

Only *explicit* limits reserve. A project on the default reserves nothing —
otherwise sixteen projects at the default of 4 would need a ceiling of 64 before
the first limit could be saved at all.

## Who can change what

- **A company admin** sets or clears a project's limit in **project settings**.
- **A platform admin** can do the same for any project in the admin area.
- **The installation ceiling** is a deployment setting, not something changeable
  from the UI.

Everyone else sees the project's limit but cannot change it.

## What a waiting session looks like

A session that is not running yet tells you which of these it is waiting for:

| Shown | Meaning |
|---|---|
| **Waiting for a free session slot** | The project's queue is full, or the shared pool is. Someone else's session has to finish first. |
| **Waiting for cluster capacity** | A slot was granted, but the cluster has nowhere to put the container yet. |
| **Starting session…** | The slot is granted and the container is coming up. |

Sessions start in the order they were asked for. Cancelling a queued session
gives its place to the next one immediately.

## Things worth knowing

- **Lowering a limit never stops a running session.** It only stops new ones
  from starting until usage falls below the new number.
- **Raising a limit takes effect at once.** Whatever was waiting starts
  immediately; there is nothing to restart and nothing to wait for.
- **Queue time is not run time.** A session that waited an hour for a slot does
  not lose an hour of its own execution budget.
- **A queued step does not make its run look stuck.** A run whose step is
  waiting for a slot reports itself as queued rather than running, and is never
  reaped for being slow.

## For operators

Capacity is a company's limit, held in the database and set on the company's own
page in the admin. A project's limit is a reservation drawn from it; projects
without one share what the reservations leave. A company with no limit of its own
is unbounded — which is also how an internal organisation is left unbilled.

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
