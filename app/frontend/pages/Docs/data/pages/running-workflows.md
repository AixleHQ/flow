# Building Workflows

A **workflow** is a named process made of **sessions**, and each session is
made of **steps**. Write the process once, and every card that enters the bound
column is handled the same way.

## Sessions and steps

**A session is one agent in its own container.** Every session of a run gets a
container started from scratch: the repositories cloned fresh, the files it is
owed copied in, nothing left over from another session. When the session ends,
everything outside `/workspace/outputs/` is gone.

**Sessions pass work forward as files.** Give the earlier session an output
spec and have its agent write the file to `/workspace/outputs/<name>`; a session
that runs after it finds the file at `/workspace/assets/<name>`. The
[Prompt guide](/docs/prompt-guide) walks through it. A later session also sees
the closing note of each session it runs after, cut to 500 characters — enough
for what happened, not for the work itself.

**Steps are a checklist inside one session.** They are not separate runs: a
session's steps go into its prompt as a numbered checklist under its
instructions, and the same agent works through them in one conversation, in
one container. Each step sees everything the steps before it did. The agent
ticks each one off as it goes, and the run page shows which step it reached.

So a session with no steps and everything in its instructions gets the same
text. Steps earn their place on a long session: the agent has to account for
each one, the run page shows where it stopped, and each step's note reaches the
sessions that run after it.

Split work into separate sessions when the parts can run at the same time, need
a different agent, runtime or resources, should wait for a person in between,
or should be retried on their own. Keep it as steps of one session when each
part builds on what the previous one left on disk or in the agent's head.

## Create a workflow

**Workflows → New Workflow**, give it a name and a description. Then add
sessions, and steps inside them. An empty name is rejected, and cancelling
posts nothing.

Sessions show up as a tree on the left, in run order top to bottom, with each
session's steps nested under it: **Add a session…** at the bottom of the tree,
**Add a step…** under each session. Click a session or a step to open its
editor on the right.

## What a session holds

The session editor is grouped into sections. Most sessions only need the first
two.

| Section | What you set |
| --- | --- |
| **Definition** | The session's name and its instructions — what the agent is being asked to do |
| **Execution** | The agent persona, the runtime the session must run on, and optionally a preferred model. Changing the runtime resets the model choice, since model names are per-product |
| **Resources** | What the agent gets on top of the workflow's **Base Resources**: wrappers, connectors, skills, assets, secrets & variables, and repositories |
| **Dependencies** | Which other sessions must finish first. Sessions with no dependency between them run at the same time |
| **Data Flow** | Input and output asset specs — the files this session expects, and the files it is expected to leave behind, matched by pattern |
| **Behavior** | **On Failure**: Fail, Retry, or Skip. **Skip Policy**: Never, If outputs exist, or Manual. **Auto-run available**: whether the session starts without waiting for a person |

> info Dependencies are what make a run parallel. Two sessions that both depend
> only on "plan" will run side by side, each in its own container, and the run
> detail shows both consoles at once.

## What a step holds

A name, its instructions, and **Required**. Nothing else: a step runs on its
session's agent, with its session's resources, in its session's container.
Flow enforces neither the order of the steps nor **Required** — if the agent
must not finish without a step, say so in the session's instructions.

## Approval sessions

Turn **Auto-run available** off on a session, and the run stops there and
waits. The waiting session shows **Approve & continue** in
[Sessions & Runs](/docs/sessions-and-runs). Use it where the cost of being
wrong is higher than the cost of waiting: merging, releasing, anything that
touches customers.

## Reusing a workflow

- **Duplicate** — copy it inside the project and edit the copy.
- **Publish to the catalog** — offer it to the whole company. It then appears
  in the [Workflow Catalog](/docs/company-workspace) with a **Copy & Configure**
  action, so another project can take it and adjust the details.
- **Run it by hand** — **Run workflow** starts a run without a card moving.

## Starting it automatically

Binding it to a board column is the common case, but a workflow can also start
on a schedule, from a Slack message, or from an incoming webhook. That is the
subject of [Triggers & gates](/docs/starting-work).
