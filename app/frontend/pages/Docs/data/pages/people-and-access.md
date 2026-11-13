# Team & Access

Membership has two levels, and they answer different questions: *who belongs to
the company* and *who works on this project*. Inside a project,
[teams](#project-teams) group its members so that runs are shared out between
their agent subscriptions.

## Roles

| Role | Can |
| --- | --- |
| **Admin** | Everything an employee can, plus members, integrations, settings, and the company-wide analytics, sessions, and assets |
| **Employee** | Work inside the projects they are on: the board and its cards, workflows, runs, resources |
| **Viewer** | Read. Boards, runs and results are visible; nothing is started or changed |

A role is per company. Being a viewer in one workspace and an employee in
another is normal, and onboarding adapts: a viewer is never asked to connect an
agent.

## Getting people in

There are two ways, and only one of them works out of the box.

**By invitation.** An admin invites an address from **Members → Invite**. The
person gets a link, accepts, and joins with the role they were given. This always
works, needs nothing set up, and is the only way in until the step below is done.
Until they accept, the invitation stays on the Members page as **Pending**. The
link works for 7 days, after which the row reads **Expired**. **Resend** on the row
mails a fresh link, and the old one stops working.

**By email domain.** Anyone signing in with an address at the workspace's domain
joins without an invitation — useful once a team is more than a handful of people.
It is switched on with **Accept new people automatically** on Settings → Access,
and it does nothing until the domain is **verified**.

### Verifying your domain

Creating a workspace proves that somebody receives mail at one address. Letting
everyone from the domain in is a claim on the whole domain, so it waits for a
record only the domain's owner can publish:

```
Name:   _aixle-challenge.yourcompany.com
Value:  aixle-domain-verification=<the token shown on Settings → Access>
```

Publish it in your DNS, then press **Check now**. DNS usually takes a few minutes
to spread, so "we could not find that record yet" means *not yet* rather than
*wrong*.

Until it is verified, nothing else about the workspace changes — invitations work
exactly as before, and the automatic-joining switch simply has no effect.

> info Verifying decides who gets **in**, not who owns the domain: a domain
> already taken by another workspace cannot be claimed again either way.

## Company members

**Members** under the company lists everyone in the workspace, searchable by
name. An admin can promote an employee to admin from the row menu.

## Project members

A project's **Members** page controls who is on this project. **Add
Collaborator** opens a picker listing only company users who are not already
here, so you cannot add someone twice. The project owner is badged and cannot
be removed; removing anyone else asks first.

Members are matched by name *and* email when you search, which is the quicker
route in a company where several people share a first name.

> info Adding someone to a project does not give them a credential. They still
> connect their own agent in [Profile](/docs/getting-started) before they can
> run anything.

## Project teams

Every run belongs to one person and uses their own agent subscription, so when
that person's quota runs out, every run they own stops. A **team** spreads the
work over several people: a named group of project members that a card can be
assigned to and a trigger can run as. Each run goes to one member, picked when
it starts. From there the run is that member's: their agent credential,
their connections, and their name on everything the agent does.

**Teams**, next to **Members** in the project's sidebar, shows one card per
team: its strategy, its members in order, the member the next run goes to
(marked **Next**), and what uses the team — triggers and cards. Each member
carries a status:

| Status | Meaning |
| --- | --- |
| **Ready** | Can take a run now |
| **On hold until** a date | Their agent ran out of quota; they are passed over until it resets |
| **Can't take runs** | Hover for the reason — no agent connected, a viewer, or no longer in the project |

### Strategies

The strategy decides who the next run goes to:

| Strategy | The run goes to |
| --- | --- |
| **Priority** | The first member down the list who can take it. One subscription is used up before the next is touched |
| **Round robin** | The next member after the one picked last, going around the list |
| **Most quota left** | The member whose agent has the most quota left. Members with no usage reading come after the ones with one, in turn |

Whatever the strategy, a member who is already running a session on the
runtime the run needs is passed over for one who is free, so parallel runs
spread over several accounts instead of piling onto one. When every member is
busy, the strategy's first choice takes the run anyway.

### Who can take a run

A member is picked only when they:

- can still start runs in the project — not a viewer, not removed;
- have an agent connected for **every** runtime the run needs — each step's
  pinned runtime, or any agent when the steps pin none;
- have none of those agents on hold.

An agent goes on hold when a run stops on its quota: until the usage window
resets, as the provider reports it, or the date the CLI's own message gives,
else for an hour. Signing in to that agent again from Profile clears the hold.
Only teams look at it — a run that belongs to one person directly still
starts, and still stops on the quota.

**When nobody can take the run, it fails at once**, before any agent starts,
and spends nothing. Its error names every member and why they were skipped —
*Anna: Kiro CLI quota exhausted until …; Pavel: has no GitHub Copilot CLI
connected* — and shows wherever a failed run does: the card, the runs list,
the chat thread's status card. There is no fallback to the person who
triggered it.

**When the quota runs out in the middle of a run**, a step set to retry on
failure is retried as the team's next member: that step and every step after
it run as them, and the handover is recorded. The retry counts toward the
step's retries. A step that is not set to retry fails the run, as it would for
anyone.

### Using a team

- **Cards.** Pick the team under **Teams** in the card's assignee list, or
  assign several cards at once from the selection bar. Every run of the card —
  from its column, from **Run**, or **Retry run** — picks again, so one card's
  runs can go to different members. The card's Runs tab and Sessions & Runs
  show who a run went to: *Planner → Anna*. The board's **Assignee** filter
  takes a team.
- **Triggers.** A trigger that does not start from a card — schedule, chat,
  webhook, task tracker, event — can run as a team: pick the team under
  **Runs as**. A column trigger's run follows the card, so a card assigned
  to a team goes to the team. See [Triggers & gates](/docs/starting-work).
- **Agents.** A workflow can hand a card to a team itself: `board_list_members`
  lists the project's teams next to its people, and `board_create_task` and
  `board_update_task` take `assignee_team_id`.

Every quota stop, in a team or not, also raises the
`workflow_run.quota_exceeded` event. An event trigger listening for it — set up
over the API or the personal MCP server — can start a workflow that tells
someone or deals with it.

### Who manages teams

| Action | Who |
| --- | --- |
| Create, rename or delete a team; set its strategy, members and their order | The project owner and company admins |
| Set a trigger's **Runs as** to a team | The project owner and company admins |
| Assign a card to a team | Anyone who can assign the card to a person |
| Leave a team | The member, from the Teams page or their profile |

- Only the project's members can be added. Someone without an agent can be
  added; they are skipped, with the reason, until they connect one.
- Adding someone mails them, with a link to leave. Taking them out mails them
  too, unless they left themselves.
- Losing access to the project — removed from it or from the company, or made
  a viewer — takes a person out of the project's teams.
- Deleting a team clears it from its cards. A team that a trigger runs as
  cannot be deleted; the error lists those triggers.
- Members added, removed or leaving, a changed strategy, and a run handed to
  another member on quota are all in the audit trail.

Over the personal MCP server the same management is `list_project_teams`,
`create_project_team`, `update_project_team` and `delete_project_team`.

### Staying out of teams

**Profile → Account → Teams** lists the teams you are in, each with
**Leave**. **Don't let anyone add me to a team** keeps you out of all of
them: turning it on takes you out of every team you are in — each project's
owner is told — and adding you is refused while it is on.
