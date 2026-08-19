# Building Workflows

A **workflow** is a named process made of ordered **steps**. Each step is one
agent session doing one job. Write the process once, and every card that enters
the bound column is handled the same way.

## Create a workflow

**Workflows → New Workflow**, give it a name and a description. Then add steps.
An empty name is rejected, and cancelling posts nothing.

Steps show up as a tree on the left: the run order top to bottom, with
sub-steps nested underneath a step that needs breaking down. Click a step to
open its editor on the right.

## What a step holds

The step editor is grouped into sections. Most steps only need the first two.

| Section | What you set |
| --- | --- |
| **Definition** | The step's name and its instructions — what the agent is being asked to do |
| **Execution** | The runtime the step must run on, and optionally a preferred model. Changing the runtime resets the model choice, since model names are per-product |
| **Resources** | What the agent gets: an agent persona, assets, skills, wrappers, connectors, repositories, and secrets & variables. A step can inherit everything the project has, or take a named subset |
| **Data Flow** | Input and output asset specs — the files this step expects, and the files it is expected to leave behind, matched by pattern |
| **Dependencies** | Which other steps must finish first. Steps with no dependency between them run at the same time |
| **Behavior** | **On Failure**: Fail, Retry, or Skip. **Skip Policy**: Never, If outputs exist, or Manual. Whether the step waits for a person before the run continues |

> info Dependencies are what make a run parallel. Two steps that both depend
> only on "plan" will run side by side, and the run detail shows both consoles
> at once.

## Approval steps

Mark a step as needing a person, and the run stops there and waits. The waiting
step shows **Approve & continue** in [Sessions & Runs](/docs/sessions-and-runs).
Use it where the cost of being wrong is higher than the cost of waiting:
merging, releasing, anything that touches customers.

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
