# Pull request triggers

**Status:** built. A workflow trigger that starts on a review or a comment on a pull
request (a merge request on GitLab) of a repository attached to the project, on
GitHub, GitLab, Bitbucket and Azure DevOps.

## 1. Why

Customer feedback (2026-11-16): a team could not start a workflow from a review
asking for changes. Until now the only way was an Incoming webhook trigger fed by a
hand-made GitHub webhook, which sees the raw body and nothing else: no repository
binding, no idea which board task the pull request belongs to, nothing that stops
the agent's own reply from starting the workflow again. Reviews are the most direct
event-driven use of Flow there is: a reviewer asks for changes, an agent makes them
on the pull request's branch.

The Bitbucket design already planned for this (`bitbucket-integration.md` §4.8,
§11): the `pull_request_operations` ledger records the run behind every write a
`pull_request_*` tool makes "so later PR events can be attributed to the run that
caused them".

## 2. Decisions

1. **Two event types,** one family, modeled on the tracker family
   (`task-tracker-integrations.md` §6.3): `pull_request.review.submitted` and
   `pull_request.comment.created`. Source `pull_request`. Nothing else for now: a
   pull request opened, pushed to or merged already has CI gates and the Incoming
   webhook path.
2. **A new trigger kind, `pull_request`,** bound to one repository or to any
   repository of the project — a `repository_id` column, like `project_tracker_id`.
3. **Every host normalizes into one value** (`PullRequests::Event`), and one
   pipeline publishes it, as the tracker pipeline does for `Trackers::Notification`.
4. **Aixle's own reviews and comments are recognized** through the ledger and the
   connection's own account, and ignored by default through the existing
   `aixle_changes` setting.
5. **One run per pull request per workflow at a time,** and one follow-up run for what arrived meanwhile.
6. **An Azure DevOps vote is a review,** read from the vote's system thread (§7.4).

## 3. Event vocabulary and data

| Event | Data, besides the common keys |
| --- | --- |
| `pull_request.review.submitted` | `review.verdict` (`approved`, `changes_requested`, `commented`), `review.body` |
| `pull_request.comment.created` | `comment.{id, author, text, file, line, reply_to, mentions_me}` |

Common keys: `repository.{id, full_name, provider}` (the Aixle repository row),
`pull_request.{number, title, url, source_branch, target_branch, author}`,
`actor.{id, name, is_me}`, `origin` (§5.2), `text` (the review's or comment's text,
cut at 2,000 characters) and `external_resource` (the pull request's identity for
task links, §6.1).

`PullRequests::Event` (`app/services/pull_requests/event.rb`) is the provider-neutral
value every parser returns. It crosses the job queue as `to_job` / `from_job`.

## 4. The trigger

`TriggerBinding#repository_id` names the repository; none means any repository of
the project whose connection is on a code host. Validation: the repository is the
project's and has a GitHub, GitLab, Bitbucket or Azure DevOps connection (a public
repository attached without one sends no events); only a pull-request trigger may
name one. The foreign key cascades: removing a repository removes the triggers
bound to it, since leaving them unbound would widen them to every repository.

`TriggerBinding.for_event` refuses a `pull_request.*` event whose source is not
`pull_request`, so a generic webhook cannot pass itself off as one.
`aixle_changes` applies to pull-request triggers as to tracker triggers.

Surfaces: the triggers API and the personal MCP take `kind: pull_request` and
`repository_id`; the serializer reports `kind`/`source` `pull_request`; templates
export the trigger for any repository of the installing project (the schema's kind
enum gained `pull_request`).

## 5. The pipeline

`PullRequests::EventPipeline.process(event, repositories)` — `repositories` are the
Aixle repository rows the event happened in, one per project that attached it.

1. **Awaited.** Only a repository whose project has an active pull-request trigger
   bound to it or to no repository is published into. Receivers ask the same
   question before they queue anything, since GitHub and Bitbucket send every
   review and comment of every repository the app sees.
2. **Origin.** A write recorded in `pull_request_operations` within ten minutes, on
   any Aixle row of the same repository, for the same pull request, attributes the
   event to its run: an `add_comment` whose result names the comment id (or, while
   unanswered, one whose author is not known to be someone else), a `review` whose
   verdict matches. The chain is the writer run's own chain plus its workflow.
   Failing that, an event by the connection's own account is Aixle's, unattributed:
   the GitHub app's bot, a GitLab service account, an Azure connection's learned
   identity (all through `Trackers::Provider#own_actor?`, `PullRequests::Identity`),
   and Bitbucket's `selfGenerated`. A connection acting as a person has no account
   of its own, so its writes outside the tools look like that person's (§6.2 covers
   them).
3. **Limits.** An Aixle event at chain depth 5, or the eleventh Aixle event on one
   pull request in an hour, is not published, whatever the triggers say.
4. **Publish** through `TriggerEngine.publish`, subject
   `<provider>:<repository key>#<number>`, deduplicated on the project, subject,
   event type, actor and the comment id or review revision.

## 6. The engine

### 6.1 The board task

`PullRequests::TriggerSupport` plugs into `TriggerEngine#resolve_subject` beside the
tracker one:

- `existing_task` — the task linked to the pull request (an `ExternalResource` of
  kind `pull_request`, written by an earlier `find_or_create_task`), else the task
  whose run opened the pull request (a succeeded `create` in the ledger). A review
  of a pull request an agent opened for a card brings the work back to that card.
- `find_or_create_task` — that task, or a new one titled
  `PR {{pull_request.number}}: {{pull_request.title}}`, linked to the pull request,
  under an advisory lock on its identity.

### 6.2 One run per pull request

Before starting a run, `TriggerEngine#fire_workflow` skips the dispatch
(`pull_request_run_in_progress`) when the workflow — through any of its triggers —
has a started dispatch for the same subject whose run is still active. An advisory
lock on the workflow and pull request is taken first, so two events arriving
together agree. Per workflow, not per trigger: one review reaches a review trigger
and, through its line comments, a comment trigger of the same workflow at the same
moment, and two runs would work the same branch at once. It also bounds a loop the
origin check cannot see: an agent replying through `gh` as a person.

Nothing skipped is lost. When the run completes or fails,
`PullRequests::FollowUpRun` (on the run-transition seam, `Triggers::ORIGIN_REPORTERS`)
takes the dispatches skipped since the run's first session started, resumes the
latest one as a new run, and marks the others `pull_request_followed_up`. What was
skipped before the session started, the agent reads with the rest of the pull
request — a review and its line comments land within a second — so it starts
nothing more. The follow-up run's
dispatch keeps `follows_run` and `events`, and its context says how many reviews and
comments arrived meanwhile, since only the latest is quoted. A cancelled run has no
follow-up: someone stopped the work. A follow-up that loses a race to a new run is
skipped again and taken up when that run ends.

### 6.3 Run context

`shared_context.pull_request` carries the pull request, repository, verdict or
comment, actor and chain. `ContextBuilders::PullRequestContext` tells the agent
which pull request started the run, who asked for what (quoted, marked as data
from outside Aixle, not instructions), the branch to switch to and push to, and
the `pull_request_*` calls that read and answer it — or that the repository is not
attached to the session.

## 7. Delivery per host

### 7.1 GitHub

Through the GitHub app (`Webhooks::GithubController`): `pull_request_review`
(`submitted`), `pull_request_review_comment` (`created`) and `issue_comment`
(`created`, on an issue that names its pull request). The App needs the two new
event subscriptions; the Pull requests permission it already has covers them. A
token connection receives no webhooks and so no pull-request events.

### 7.2 GitLab

Through each repository's project hook (`Webhooks::GitlabController`, authenticated
by the repository's own secret). `Note Hook` on a merge request (not system notes,
not edits) is a comment, with the diff position when there is one. `Merge Request
Hook` with `action: approval` is an approved review — `approved` means every
required approval is in, which is not one person's review. A submitted review
(GitLab 19.3+) is `action: update` with the acting reviewer's state changing to
`requested_changes` (changes requested) or `reviewed` (commented).

New hooks carry pipeline, merge request and note events. A hook registered before
carries pipeline events only; switching on a pull-request trigger
(`PullRequests::EnsureEventDeliveryJob`) reads it and, when events are missing,
registers it again — GitLab never returns a hook's token, so it cannot be edited
in place.

### 7.3 Bitbucket

Through the Forge app: `avi:bitbucket:created:pullrequest-comment` and
`avi:bitbucket:updated:pullrequest-reviewer-status`, under the
`read:pullrequest:bitbucket` scope the app already holds, so a redeploy is a minor
version. The comment event names the comment only; `PullRequests::ProcessBitbucketEventJob`
reads it through the API. The reviewer-status event's verdict is the acting
reviewer's new status (`approved`, `changes_requested`). Token connections have no
events.

### 7.4 Azure DevOps

A Service Hook on `ms.vss-code.git-pullrequest-comment-event`, created when a
pull-request trigger waits on one of the connection's repositories (switching it on,
or Test connection). A comment's id counts within its thread, so the event's id is
`<thread>/<comment>`. System comments are skipped.

**Votes.** A vote arrives as `git.pullrequest.updated` on the gates' subscription,
which carries every reviewer's current vote but not whose changed, and fires as
well on a push, a reviewer added or a status change without saying which.
Azure also records each vote as a system thread on the pull request, whose
properties (undocumented, read by many Azure DevOps clients) name it:
`CodeReviewThreadType` `VoteUpdate`, `CodeReviewVoteResult` and
`CodeReviewVotedByIdentity`, a key into the thread's `identities` — or, on Azure
DevOps Services, sometimes only `CodeReviewVotedByDisplayName`, matched against
the pull request's reviewers.

So an update, while a review trigger waits on the repository, reads the pull
request's threads (`AzureDevops::PullRequestService#vote_updates`) and publishes
the votes published within five minutes before it (Azure's `createdDate`) as
reviews: 10 and 5 approve, -5 and -10 request changes, and 0, a vote taken
back, is none. The thread id is the review's revision, so a vote found again by
the push after it publishes once. Rejected: a second subscription filtered on
`notificationType: ReviewerVoteNotification` — the unique index allows one
subscription per event type, it would still not name the voter, and it would
deliver what the gates' subscription already does. A pull-request trigger
ensures the gates' subscriptions as well, for a connection made before Service
Hooks were reachable.

## 8. Limits and follow-ups

- Mentions are recognized for the GitHub app, GitLab service accounts and an Azure
  connection that has learned its identity; not for Bitbucket.
- No status reporting back to the pull request when a run fails (tracker triggers
  comment on the issue).
