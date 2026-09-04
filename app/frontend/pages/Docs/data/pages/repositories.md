# Repositories & Integrations

Two pages that together decide what an agent can touch outside Flow.

## Integrations

An **integration** is an account Flow connects to on the team's behalf:
GitHub, GitLab, Linear, Slack, and Coder. Connect one from the page's
**Connect** menu — GitHub through its app install, GitLab with a token, and so
on.

The table lists project integrations and company-wide ones together, each with
a **Scope** badge, so it is always clear whether a connection is yours alone or
inherited from the company. Removing one asks for confirmation.

## Repositories

A **repository** is a Git repo agents can read, work in, and push to. Each row
shows the branch the project works from, and company-wide repositories appear
in the same table with their scope marked.

Link the repos a project actually needs — not every repo the company owns. A
step only reaches the repositories its Resources section lists.

## What this unlocks

With a repository linked and an integration connected, a run can:

- read the codebase it is asked about,
- push a branch and open a pull request in your own remote,
- move the ticket that started the work.

Nothing in Flow rewrites your Git history behind your back: agents work on
branches, and what lands is what your review process lets land.

> warning Access is inherited by every step that lists the repository. If a
> workflow should not be able to push, do not give its steps the repo — that is
> the control, not an agent instruction asking it politely.
