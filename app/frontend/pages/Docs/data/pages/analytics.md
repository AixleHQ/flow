# Analytics & Cost

Agent work costs money per run, so Flow counts it everywhere: per card, per
project, per company.

## Project analytics

The project's **Analytics** page answers "what did this cost us, and where did
it go?"

- **Period** — pick the window; every panel follows it.
- **Scope** — switch between all sessions and workflow-driven ones, so ad-hoc
  experiments do not muddy the numbers for an automated process.
- **Participant** — narrow to one person's work.
- **Cost & token usage** — spend and tokens over the period.
- **Agent activity** — sessions and cost per runtime, so you can see what your
  Claude Code and Codex usage actually cost side by side.
- **Workflow breakdown** — per workflow, which is how you find the process that
  is quietly expensive.
- **Contribution heatmap** — activity over time at a glance.

## Company analytics

Admins get the same questions asked across every project: a per-project
breakdown, and a **sources** panel showing where sessions came from — the
board, a schedule, Slack, a webhook, a person — each as a share of the total.

Large numbers are abbreviated (thousands of tokens, thousands of dollars) so a
row stays readable.

## Where else cost shows up

- On a **card**, in its Analytics tab — what this one piece of work cost.
- On a **run**, in the header totals and per step.
- In your **Profile → Usage** — your own consumption, and the time left on any
  usage window that applies to you.

> tip Two numbers explain most surprises: cost per session on
> [Overview](/docs/project-home), and the workflow breakdown here. A workflow
> with a retry loop shows up in the second long before anyone notices in the
> first.
