# Project teams

**Status:** built, 2026-11-11 — all three phases. Revised 2026-11-13 after the
first feedback: an expired login takes a member out of the pick, and a quota or
login stop hands the run on whatever the step's `on_failure` (decision 3). The code lives under
`ProjectTeams::` (`app/services/project_teams/`); `Teams::` is the Microsoft Teams
integration.
The user-facing guide is the docs portal's **Project teams** page
(`app/frontend/pages/Docs/data/pages/project-teams.md`).

A **team** is a named group of a project's members with a rule for choosing one of
them. A board task can be assigned to a team, and an off-board trigger (schedule,
chat, webhook, tracker, custom event) can run as a team. At launch the team resolves
to one person, and from there nothing changes: the run, its step sessions, the agent
credential, the personal MCP connections and the audit trail all belong to that
person, exactly as they do for a run owned by an assignee or a trigger's Runs as
today.

## Problem

Agents run on their owner's own agent subscription. A card's run belongs to its
assignee (`TaskService.run_owner_for`); an off-board trigger's run belongs to the
trigger's Runs as (`TriggerBinding#created_by`). When that person's quota runs out,
every run they own fails with `quota_exceeded`, and keeps failing until someone
notices and picks another person by hand.

Teams that share the load across several members' subscriptions have to build the
rotation themselves: a workflow that reassigns cards when a run fails. That works for
cards, but not for triggers — an agent has no tool to change a trigger's Runs as, and
the REST endpoint accepts browser sessions only. A scheduled trigger keeps running as
the person without quota.

A team moves the choice of person into the platform, for cards and triggers alike.

## Decisions

| # | Question | Decision |
|---|---|---|
| 1 | No member can take the run | Fail the run at once, with the reason for every member who was skipped. No fallback to whoever triggered it. |
| 2 | Is a card bound to one member? | No. Each run of a card assigned to a team picks the best member at that moment. |
| 3 | Quota hit in the middle of a run | The step runs again as the team's next member, whatever its `on_failure` and without spending a retry. A login failure is handed on the same way. (Until 2026-11-13 this needed the step set to retry, and spent a retry: teams had to turn retry on for every failure, costly steps included, to survive a quota stop.) |
| 4 | Consent of the member | Members are notified when added and can leave a team themselves. A profile setting, off by default, keeps a user out of every team. |
| 5 | Who manages teams | The project owner and company admins — the same people who may change a trigger's Runs as (`change_run_as?`). |

## Data model

```
project_teams
  id, project_id (FK, not null), name (unique per project),
  strategy        -- priority | round_robin | most_remaining
  last_picked_user_id  -- the round-robin cursor
  created_by_id, timestamps

project_team_members
  id, project_team_id (FK, not null), user_id (FK, not null), position,
  added_by_id, timestamps
  unique (project_team_id, user_id)

board_tasks.assignee_team_id      -- FK project_teams, nullable
  check: num_nonnulls(assignee_id, assignee_team_id) <= 1

trigger_bindings.run_as_team_id   -- FK project_teams, nullable

workflow_runs.team_id             -- FK project_teams, nullable: the run's owner was picked from this team

agent_credentials.quota_exhausted_until  -- datetime, nullable

users.exclude_from_teams          -- boolean, default false
```

**Why a second column, not a polymorphic assignee.** About fifty backend places read
`task.assignee` as a `User` — resources, ransack filters (`q[assignee_id_eq]`), board
view presets, Typelizer types, the session tools. A polymorphic assignee would touch
all of them; a separate `assignee_team_id` touches only the places that learn about
teams. The check constraint keeps "one of the two, or nobody".

**`created_by` on a trigger.** Today it means both "who set this up" and "who it runs
as". With `run_as_team_id` set, `created_by` stops being the run owner and stays as
the author. Clearing the team brings `created_by` back as Runs as, so setting a team
must not overwrite it.

## Picking a member

One service, `ProjectTeams::Picker`, called in one place: `WorkflowService.enqueue`
takes `team:` and hands the run to the member it picks. Every launch reaches it:

- a card assigned to a team — its Run button and its column trigger record the
  team in the launch event's data (`team_id`, next to `requested_by_id`), and
  `TriggerEngine.fire_recorded_launch` passes it on. `TaskService.run_owner_for` is
  unchanged: a team card has no `assignee`, so the event's actor stays the person
  who caused the launch;
- `TriggerEngine.fire_for_binding` — every off-board trigger with `run_as_team`;
- `WorkflowService.retry_step` on a closed run — the new run picks from the
  failed run's team again.

Session tools act as `task.assignee || workflow_run&.user`, so on a team card the
agent acts as the picked member — the run's owner.

### Eligibility

A member is a candidate when all of these hold:

1. `project.accessible_by?(member)` and an active, non-viewer membership in the
   company — `TaskService.can_own_runs_in?` minus its "any credential" clause, which
   the next rule replaces;
2. the member holds a credential for **every runtime the run will need**: each
   step's `required_agent_runtime`, plus the run's `agent_runtime` if one was
   requested. Steps with no pinned runtime resolve from the member's own default
   (`SessionService`, `app/services/session_service.rb:217`), so they need no more
   than one credential of any kind;
3. each of those credentials is a working login: `active` (not condemned by the
   refresh sweep) and not `unrecoverably_expired?` — the test
   `SessionService#preflight_agent_credential!` applies at launch. A member who
   fails it shows as **Login expired** on the Teams page;
4. none of those credentials has `quota_exhausted_until` in the future.

Rule 2 also closes a gap that exists today for single assignees: an assignee with
some credential, but not the runtime a step pins, gets a nil credential and the step
dies on the CLI's login error (comment at `app/services/task_service.rb:405`).

### Strategies

| Strategy | Pick | Notes |
|---|---|---|
| `priority` | first candidate by `position` | Drains one subscription before the next. |
| `round_robin` | first candidate after `last_picked_user_id`, wrapping | The cursor moves under `team.with_lock`, so two triggers firing together do not pick the same member. |
| `most_remaining` | candidate with the most quota left | Read from the cached `Agents::SubscriptionUsageService` entry (3-minute TTL; the vendors answer 429 to anything chattier). A credential's score is the share left in its fullest window (100 − utilization), so Kiro credits and Claude's 5-hour and weekly windows compare on one scale; a candidate's score is the minimum over the runtimes the run needs. Candidates with no reading go after the ones with a reading, in round-robin order. |

The strategy orders the candidates; the first of them not already running a session
(`TerminalSession.active`) on a runtime the run needs takes it. Parallel runs then
spread over accounts instead of stacking on one and hitting a provider's
concurrent-session limit; when every candidate is busy, the strategy's first choice
still takes it. Admission pools stay per project and per runner, not per credential.

The picker never calls a vendor synchronously on the launch path for more than one
uncached credential (`Picker::UNCACHED_READINGS`); a miss beyond that counts as
"no reading". `round_robin` and `most_remaining` move the cursor; `priority` does
not.

### No candidate

The run is created with `failure_reason: "team_unavailable"`, every step run failed
with a message naming each member and why they were skipped ("Anna: Kiro CLI quota
exhausted until 2026-11-14 09:00 UTC; Pavel: has no GitHub Copilot CLI connected").
It belongs to whoever caused the launch — the person who pressed Run or moved the
card, or the trigger's author (else the team's creator) — and spends nothing:
`WorkflowService.dispatch!` ends it with `fail_before_start!` before any execution
exists, as it does a refused runner, and comments on its card. Ending it at dispatch
rather than in `enqueue` lets the trigger's dispatch record the run first, so the
failure reaches the places people already look: the runs list, the card, the chat
status card (`Chat::RunFailure`) and the trigger's failure reporting.

There is no fallback to the person who triggered the run. For a card, `requested_by`
stays the fallback only for an **unassigned** card, as today.

## Quota exhaustion

`CompleteStepActivity#quota_failure_result` already knows which credential hit the
quota. It now also sets that credential's `quota_exhausted_until` (`QuotaHold`),
from the first source that has it:

1. the `resets_at` of every usage window at 99% or more — Kiro's `nextDateReset`
   from GetUsageLimits (`KiroCliAdapter#credit_window`), Claude's 5-hour or weekly
   window (`ClaudeCodeAdapter`) — read fresh once, the latest of them;
2. the date in the CLI's own message, where it prints one ("You will regain access
   on …");
3. a fixed hold of one hour, after which the credential is tried again.

The hold is written with `update_column`: `updated_at` keys the usage cache, and a
hold is not a new login. A new sign-in (`AgentCredential.from_artifacts` with
`new_authorization: true`) clears it; a replaced credential is a new row without
one; a hold in the past is ignored. The field is not team-specific — a run owned by
one person is not affected by it — and the Teams page shows it per member.

## Handing a run on

A step that failed on quota is never retried for a run without a team
(`@quota_error_step_run_ids`, `WorkflowExecutionWorkflow`): the same account would
fail again.

For a run with `team_id`, a step that stopped on its owner's quota or login
(`CompleteStepActivity` reports `quota_error` or `auth_error`) goes through
`workflow_reassign_run_owner_activity` (`ProjectTeams::Handoff`) before anything
else:

1. pick the next member with the team's strategy, passing over the run's current
   owner and every member the run has already left (the `run_owner_reassigned`
   audits) — a failed login puts no hold on the credential, so without that two
   members whose logins both fail would pass the run back and forth;
2. none → a quota stop fails the step and the run, with the same `team_unavailable`
   message; a login failure goes on to the step's `on_failure`, as it does without
   a team;
3. otherwise set `workflow_runs.user_id` to the new member, clear the run's
   `failure_reason` and `failed_agent_credential_id` (the stop no longer says why
   the run ends), audit the change (`run_owner_reassigned`: from, to, step run,
   quota or login), and run the step again — the new step run's session is created
   for `workflow_run.user` (`SessionService`), so it and every later step run as the
   new member.

The handoff does not depend on `on_failure` and does not count toward
`max_retries`. It happens at most once per member. Earlier steps' sessions keep
their original owner.

This changes workflow code that runs for in-flight executions, so the branch sits
behind `Temporalio::Workflow.patched("team-handoff")` in
`WorkflowExecutionWorkflow#recover_from_step_completion_failure`, which
`WorkflowExecutionWorkflowV2` inherits (see `docs/architecture/temporal-versioning.md`).
Executions started before it keep the earlier `team-quota-retry` behaviour: a quota
stop handed on only when the step was set to retry, spending a retry. The pick runs
in the activity, never in workflow code.

A run without a team behaves as before.

## Membership

- **Who can be added.** Project members only — the same set
  `WorkflowTriggers::RunAs.eligible_users` offers for Runs as. A member without a
  credential can be added; the picker skips them and the failure message says why.
- **Opt-out.** A profile setting, "Don't let anyone add me to a team"
  (`users.exclude_from_teams`, off by default). While it is on, adding the user is
  refused. Turning it on removes the user from every team they are in, mailing each
  project's owner (`TeamMailer.member_opted_out`).
- **Notification.** Adding a member mails them (team, project, who added them, a
  link to leave). Removing them mails them too — taken out in the editor, or by a
  cascade below, with its reason — unless they left themselves or asked to stay out
  of teams.
- **Leaving.** A member can remove themselves from any team, whatever their role.
- **Cascades.** Losing access to the project (collaborator removed, company
  membership revoked or downgraded to viewer) removes the member from the project's
  teams (`ProjectTeams::Management.prune!`, from `ProjectCollaborator` and
  `CompanyMembership` commit callbacks). The picker checks the same things again,
  for anyone a write that skipped the callbacks left behind. Deleting a team nullifies `assignee_team_id` on its tasks and is refused
  while a trigger runs as it, listing those triggers.
- **Audit.** Member added, removed, left; strategy changed; a run's owner switched by
  a quota or login handoff.

## Permissions

| Action | Who |
|---|---|
| Create, rename, delete a team; add or remove members; change strategy | project owner, company admins (`change_run_as?`) |
| Leave a team | the member |
| Assign a card to a team | whoever may assign the card to a person |
| Set a trigger's Runs as to a team | project owner, company admins (`change_run_as?`) |

## Surfaces

- **Project → Teams** (`/company/projects/:id/teams`, the sidebar item after
  Members; `Web::Company::Projects::TeamsController`). One card per team: its
  strategy; its members in order, each with whether they can take a run now
  (Ready, On hold until a date, Login expired, or Can't take runs, the reason on hover); the
  member the next run goes to, marked Next (`ProjectTeams::Picker.preview`, which
  locks nothing, moves no cursor and asks no vendor); what uses the team; Leave and
  Edit. The editor sets name, strategy and member order, and deletes the team. The
  page writes through this controller, so there is no separate `api/v1` teams
  endpoint.
- **Board.** The assignee picker gains a Teams section; a card shows the team, and
  each run shows the member it went to ("Planner → Anna"). The board filter accepts a
  team.
- **Trigger form.** Runs as: a person or a team.
- **Profile.** The opt-out setting; the list of teams the user is in, with Leave.
- **REST (`api/v1`).** `assignee_team_id` on task create/update, bulk
  `set_assignee` and board filters (`q[assignee_team_id_eq]`, view presets);
  `run_as_team_id` on trigger create/update (null clears it; naming a person
  without it clears it too); each trigger carries `run_as_team`, and
  `WorkflowTriggers::RunAs.options` lists teams next to members.
- **Personal MCP tools.** `list_project_teams`, `create_project_team`,
  `update_project_team`, `delete_project_team`; `assignee_team_id` on
  `create_board_task` / `update_board_task`; `run_as_team_id` on
  `create_workflow_trigger` / `update_workflow_trigger`; teams in
  `list_workflow_triggers`.
- **Session tools.** `assignee_team_id` on `board_create_task` / `board_update_task`;
  teams in `board_list_members`. With these, a workflow can hand a card to a team, and
  no agent ever needs to rotate people.
- **Event.** `workflow_run.quota_exceeded`, raised for every quota stop
  (`ProjectTeams::QuotaEvent`, source `aixle.workflow_run`) with the run, workflow,
  task, owner, team, runtime, hold and the trigger that started the run. An event
  trigger (kind `event`) listens for it. A run that this event started does not
  raise it again, and `TriggerBinding.for_event` matches `workflow_run.*` events
  only from that source, so a webhook cannot pass itself off as one.
- **Trackers.** A team has no counterpart in Jira, Linear or the others; assigning a
  card to a team pushes nothing to the tracker.

## What does not change

- A session belongs to one person. Credentials, personal MCP OAuth tokens, cloud
  connections, config item access records and the Kubernetes namespace all come from
  that person (`SessionCompany.agent_credentials_for`, `SessionService` preflights).
- A run's owner is fixed at launch, except for the handoff above.
- A card assigned to a person, and a trigger running as a person, behave as today.

## Phases

All three shipped together:

1. **Teams for triggers.** Model, Teams page, picker with `priority` and
   `round_robin`, Runs as = team, `quota_exhausted_until`, `team_unavailable`,
   opt-out, notifications, personal MCP tools.
2. **Teams as assignees.** Board UI, filters, bulk assign, session and personal tools.
3. **Retry and balance.** `most_remaining`, the quota retry behind the
   `team-quota-retry` patch (replaced by `team-handoff` on 2026-11-13), and the
   `workflow_run.quota_exceeded` event.

## Open points

- **Provider terms.** A run still uses one person's own account, as Runs as does
  today; what is new is that `most_remaining` and the handoff move work to
  another member's subscription when one member's limit is reached. Whether that
  fits each provider's terms is for legal to assess. Nothing in the code restricts
  which credential kinds a team may use.
