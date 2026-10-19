# Changelog

All notable changes to Aixle Flow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/) from 1.0.0 —
what each kind of bump promises, and how a release is cut, is in
[docs/operations/releasing.md](docs/operations/releasing.md). Entries a *user*
sees in the product carry a product area from
[docs/product/changelog-product-areas.md](docs/product/changelog-product-areas.md)
as their prefix; repository-level entries a *contributor* needs — licensing,
governance, community health — carry none.

## [Unreleased]

### Added
- **Admin**: the admin opens on a dashboard. Tiles show active companies by
  billing status, members and projects, and the period's worker hours, busy
  hours (and how much of them is not on a paid plan) and successful sessions.
  Below them, one row per company for a day, week, month or custom range: worker
  hours, busy hours, min/max and peak workers, utilization, queue wait, and
  successful and failed sessions, each compared with the period before, with
  whether the company pays, is on a trial, is blocked or is managed by Aixle.
  History back to 2026-09-25 fills in by itself after the upgrade.

### Changed
- **Admin**: the admin uses the Aixle Flow theme.
- **Admin**: where Aixle hosts, a company runs free only when it is ticked
  Managed by Aixle. A worker limit can no longer be cleared unless the company is
  managed. Setting a company running by hand when it has no Stripe customer, such
  as letting a blocked one back in, now starts a new trial instead of running it
  free; it needs a card once that trial is spent. On upgrade, active companies
  that already ran free (no limit, or no Stripe customer) are ticked Managed by
  Aixle; untick one to put it on the trial.

### Fixed
- **Admin**: saving a company in the admin no longer turns its settings into a
  quoted string, quoted again on every later save. Settings already saved that
  way are restored on upgrade.

## [1.3.0] - 2026-10-17

### Added
- **Integrations**: connect Bitbucket Cloud. A workspace admin installs the Aixle
  Flow app on the workspace and connects it from **Workspace settings → Aixle
  Flow**; agents then act as the app's bot with short-lived tokens, and
  Bitbucket reports CI as it finishes. A workspace, project or repository access
  token, or a personal API token, connects without the app. Jira and Bitbucket
  are now under one **Atlassian** entry in the Connect menu.
- **Repositories**: attach Bitbucket repositories, and public repositories from
  bitbucket.org, and clone and push them in sessions. They stay attached when the
  repository or the workspace is renamed in Bitbucket.
- **Repositories**: agents open, update, comment on, review and merge pull
  requests on GitHub, GitLab and Bitbucket with the same `pull_request_*` tools.
  A merge goes ahead only if the pull request is still at the commit the agent
  reviewed, a call repeated after a timeout never opens a second pull request or
  comment, and merging can be turned off per connection. A run started from a
  tracker issue puts the issue key in its branch names and pull-request titles,
  so Jira links them to the issue.
- **Triggers & gates**: a `bitbucket_pr_statuses_completed` gate waits for every
  build status on a Bitbucket pull request's head commit — Pipelines or any
  other CI.
- **Integrations**: operators who run their own Bitbucket app set
  `BITBUCKET_FORGE_APP_ID` and `BITBUCKET_FORGE_ENVIRONMENT_ID`, and
  `BITBUCKET_FORGE_INSTALL_URL` for the install button (see
  `docs/reference/configuration.md` and `bitbucket-app/README.md`). Without the
  first two Bitbucket connects with tokens only.
- **Tasks**: a subtask's agent sees its parent epic's number, title and id, and
  `board_list_tasks` can list an epic's subtasks (`parent_task_id`).
- **Sign-in & onboarding**: an admin can skip connecting an agent during
  onboarding ("Skip for now", then confirm) and still invite members and manage
  the company. Until they connect an agent in Profile settings, they cannot start
  workflows, sessions or the Builder.

### Changed
- **Tasks**: any project member who is not a viewer can set up a board and add,
  rename, reorder or delete its columns from the personal MCP server, and a board
  template installs its columns for them. Until now only the project owner could,
  although the board screen already let every member edit columns.
- **Sessions & Runs**: a workflow run, session or Builder launch by someone with
  no agent login in the company is refused up front with "No agent credentials.
  Connect an agent in Profile settings to run workflows." It used to start and
  then end as cancelled with "Agent credential unavailable". A triggered run is
  skipped with the same reason, and a step whose agent is not connected fails
  with a message naming that agent.
- **Sessions & Runs**: a workflow step's initial context summarizes only the
  steps it depends on, directly or through others, and only the latest completed
  or skipped attempt of each. Finished steps on independent branches no longer
  appear, and a step with no dependencies gets no previous-steps summary. Files
  from earlier steps are unaffected.
- **Sessions & Runs**: when the generated context exceeds `CONTEXT_TOKEN_BUDGET`,
  every sub-step `→ data:` line in the previous-steps summary is dropped, whatever
  its length (before, a long one was only shortened), and other notes over 100
  characters are cut. A session's `context_metadata` gains a `rendering` object
  with the final size, estimated tokens, compressed sections and whether it is
  still over budget.
- **Sessions & Runs**: the Output Rules now say "Use only the MCP servers and
  tools needed for the task" instead of "Use all available MCP servers and
  tools". This is in the context of every session except the Aixle Builder's.
- **Aixle Builder**: workflow guidance favors one canonical specification,
  resources scoped to each step and reviews with distinct purposes.

### Fixed
- **Repositories**: picking the chosen integration, repository or branch again in
  **Add Repository** keeps it instead of clearing it and the fields below. When the
  integration has nothing left to add, the repository field says why: every
  repository it reaches is already in the project, or it reaches none.
- **Sessions & Runs**: a running step whose owner does not share active sessions
  now says its live view is private, and how the owner can share it, instead of
  showing "Session starting…" until the step ends.
- **Workflows**: step, sub-step, workflow and task names that an agent wrote
  HTML-escaped ("Plan &amp; release next batch") are stored and shown as plain
  text. Existing step, sub-step and task names are decoded by a migration.
- **Triggers & gates**: a GitLab pipeline webhook no longer fails with a server
  error on the first delivery each web server receives, so a CI gate on that
  pipeline resolves when the pipeline ends instead of at the next reconcile sweep.
- **Sessions & Runs**: an agent session or workflow step gets up to ten minutes to
  set itself up (skills, repositories, BMAD) before the agent starts, up from five.
  A slow package registry used to fail the step with "Unresolved exec; no
  reservation is held for this phase". The BMAD install now gives up after three
  minutes and the session goes on without it. If setup still runs out of time,
  the error says that an earlier attempt timed out or lost its worker.
- **Sign-in & onboarding**: a viewer's onboarding shows a preview of one of the
  company's workflows and its first steps. It showed the generic text whenever
  that workflow had steps, and could pick an archived workflow.
- **Tasks**: `board_get_comments` filtered by human author returns people's
  comments. The only human value it offered, `user`, matched nothing; it now
  accepts `human` (and `system`), and `user` still works as an alias.

## [1.2.2] - 2026-10-15

### Changed
- **Tasks**: in the board tasks API (`GET …/board/tasks`), `q[title_cont]` and the
  other `_cont`, `_start` and `_end` predicates now match case exactly. Use
  `q[title_i_cont]` (or `_i_start`, `_i_end`) to ignore case, as the board's search
  box does.

### Fixed
- **Repositories**: the branch picker for a GitLab repository lists all of its
  branches. It showed only the first 20 by name, so a branch further down the
  alphabet, such as `develop`, could not be picked or found by search.
- **Integrations**: the Aixle Flow app for YouTrack (1.0.1) no longer takes over
  an existing `aixle-flow` account that can sign in or has its own tokens. It
  reuses only the service user it created; any other account with that login
  stops the setup with an error, so nobody who can sign in as it gains the
  connected projects.
- **Integrations**: the YouTrack guide and the Aixle Flow app in YouTrack now
  send you to the project's **Integrations** page to connect YouTrack. They
  pointed at the Trackers page, which has no Connect button.
- **Connectors**: connecting a connector that signs in with OAuth now asks for
  offline access whenever its sign-in server offers it, so the connection renews
  itself instead of asking you to connect again once the first token expires.
  Sign-in may show a consent screen it did not show before. A connector that names
  the permissions it needs when it asks you to sign in now gets exactly those.
  Existing connections change only when they are reconnected.
- **Company settings**: a workspace's own sign-in connection to Microsoft Entra
  ID can be verified. **Verify** links the account you sign in with to yours,
  takes the address from the username when Entra sends no email, and shows on the
  Access screen why a sign-in failed. It used to fail silently and leave the
  connection *Not verified yet*.
- **Company settings**: adding an SSO connection with a name another of the
  company's connections already uses now shows an error on the name instead
  of failing with a server error. Names are saved without surrounding spaces.
- **Profile**: a Claude Design login the vendor refused stays cleared until you
  reconnect it. A session that still held the old copy no longer writes it
  back, so the server stops retrying the dead login.

## [1.2.1] - 2026-10-13

### Changed
- **Sessions & Runs**: a workflow step's agent starts with a shorter context,
  so every model call in the session costs fewer tokens. The context stops
  repeating what the agent already gets elsewhere: the step's instructions in an
  unattended run (they are already its starting prompt), the task's comments,
  the tools' descriptions, the sub-step tool notes and the outputs-directory rule.
  A task description up to 1,500 characters is shown whole instead of cut at
  500; a longer one is left to `board_get_task`. Comments are read with
  `board_get_comments`, which now takes a `limit` that returns only the newest.

### Fixed
- **Company settings**: the final invoice after cancelling a subscription now
  bills usage up to the minute of cancelling, including the hour under way,
  and is issued and charged within a few minutes instead of an hour later. The
  Billing tab shows it being prepared, then links to it. A declined final
  invoice is emailed to every admin and must be paid before a new card is added.
- **Triggers & gates**: a run started by an incoming webhook hands the request's
  JSON body to every step's agent in `/workspace/assets/webhook-payload.json`.
  It used to reach the agent only through a card the trigger created, so a
  trigger set to run without one gave the agent nothing to work on.
- **Sign-in & onboarding**: an agent login that went wrong while connecting an
  agent — a dead terminal, an auth code pasted into the shell — can be dropped
  with **Start over**, which opens a fresh login in its place. The card used to
  stay in *Connecting* on the dead terminal for up to 23 hours.
- **Profile**: the **Authenticate** dialog has the same **Start over** for a
  login that went wrong. Nothing the dropped login captured is saved.
- **Sessions & Runs**: a workflow run's Duration counts from the moment its
  first session leaves the queue, so time spent waiting for a free slot no
  longer makes a run look slower than it was. A run still waiting for its
  first session shows "—", and sorting by Duration follows the same value.
  Each session card on a run's page is timed from its session's start the same way.
- **Tasks**: run and step durations on a task's card, its runs and its
  statistics leave out time spent in the queue, matching Sessions & Runs. A
  task's total run time no longer counts each run once per step.
- **Analytics**: a workflow's total and average run time leave out queue time
  and count each run once; a run with several steps used to be counted once per step.
- **Triggers & gates**: a run's status card in Slack or Teams shows when the
  run started executing, and how long it took, without the time it waited in the queue.
- **Sessions & Runs**: a Claude Code session's terminal log scrolls back through
  the whole conversation again, live and after the session ends. It used to show
  only the last screen, frozen on the spinner.
- **Sign-in & onboarding**: a request whose query string carries `user` as a
  plain value (`?user=x`) is answered normally instead of failing with a server
  error. The sign-in rate limiter read that parameter as a nested sign-in form
  on every request, including requests to addresses that do not exist.
- **Tasks**: deleting a board column no longer runs one query per column
  transition and per remaining column. The column's transitions are removed and
  the remaining columns renumbered in a constant number of statements.

## [1.2.0] - 2026-10-09

### Added
- **Profile**: set a password under Profile → Security if you were onboarded
  without one, or change the one you have. Every set, change or reset emails
  you and signs you out on your other devices; this one stays signed in.
- **Sign-in & onboarding**: **Forgot password?** on the sign-in screen emails a
  single-use link, valid for an hour, to choose a new password.
- **Sessions & Runs**: the **Model** field in **New session** names the default
  model the session will run on (e.g. `Default · Claude Opus 4.8`), taken from
  the runtime's default in Profile, and lists it first in the dropdown. A
  runtime with no default set keeps `Default (runtime selects)`.

### Changed
- **Docs**: the User guide overview and *What Flow is* describe every way a
  run starts (column, **Run**, schedule, Slack or Teams, webhook, tracker),
  whose agent credential it runs on, the session queue, and where results go
  back — not only a card moving on the board. *Triggers & gates* adds Teams
  messages, tracker events and who a run belongs to.
- The `flow-web` image is about 130 MB smaller (about 35 MB to pull): it no
  longer carries the native extensions its gems ship for Ruby versions other
  than the one it runs. The `flow-grok` image is about 160 MB smaller (about
  65 MB to pull) without a second, unused copy of the Grok CLI binary.
- **Company settings**: cancelling the subscription stops it at once instead of
  at the end of the billing period, so workers are no longer billed for the
  rest of a month nobody wants. Usage up to the cancellation goes on a final
  invoice, and the email to admins says the subscription is cancelled. A
  cancellation already scheduled for a period's end can still be taken back
  until its date.
- **Tasks**: a link to another site in a card comment opens in a new tab, as
  one in the card description already did; links within Flow stay in the same
  tab, in the description too.
- **Templates**: links to other sites in a template's readme and setup notes,
  and in the setup page of an installed template, open in a new tab.

### Fixed
- **Sign-in & onboarding**: sign-in and magic-link rate limits now count attempts
  sent as JSON, not only form posts, so the per-account brute-force limit can no
  longer be bypassed by changing the request's content type.
- **Sessions & Runs**: usage reported for a session is accepted only when the
  batch carries that session's key. Token and cost figures can no longer be
  written to a session by anyone who has seen its (non-secret) terminal link.
- **Repositories**: `gh` inside a session is signed in for the attached GitHub
  repositories on Kubernetes deployments too, so agents can read checks, watch
  Actions runs and open pull requests without building a token by hand. Until
  now it only worked with the Docker runtime.
- **Company settings**: unticking **Managed by Aixle** on a company puts it
  on the free allowance, or stops it until a card is added if it has already
  used the allowance or its subscription has ended. It no longer shows an
  Active subscription with a Cancel button that refuses. Unticking needs a
  worker limit, as creating a paying company does. An active workspace with no
  subscription is offered **Add a card** instead of **Cancel subscription**.

## [1.1.0] - 2026-10-09

### Added
- **Tasks**: edit a comment you wrote on a card, for three hours after posting
  it.
- **Sessions & Runs**: sort the list by tokens, cost, duration or start time
  (highest first; click again to flip), and filter it by date range and by
  workflow.
- **Analytics**: every period picker offers a custom date range next to the
  presets — in project and company analytics, the Usage tab of Profile and a
  member's page — so a two-week sprint can be looked at on its own.
- **Company sessions**: the same sorting and date-range filter, plus a filter
  by project.
- **Docs**: a changelog page at `/changelog`, linked next to Docs and API in
  the docs header and from the landing page, lists every release by product
  area. It reads `CHANGELOG.md` from the public repository, and the copy the
  installation shipped with when GitHub cannot be reached.

### Changed
- **Sign-in & onboarding**: an AWS Marketplace installation opens sign-in, or
  the projects page for someone already signed in, instead of the landing
  page.
- **Sessions & Runs**: agent CLIs raised to Claude Code 2.1.294, Codex 0.161.0,
  Gemini CLI 0.60.0 and Grok 1.0.46, and Cursor CLI (2026.10.01-e373342) and
  Kiro CLI (2.28.0) are now pinned like the others instead of installing the
  vendor's newest release on every image build. Gemini CLI stays below 0.61,
  whose `--yolo` stops at a confirmation dialog whenever the agent edits a
  build file (`package.json`, a lockfile, a `Dockerfile`). Antigravity CLI
  stays at 1.1.27: 1.3.1 ignores the setting the image turns its telemetry
  off with.
- **Company settings**: on the hosted product a company created by a platform
  administrator now pays like a self-serve signup — it starts on the free
  allowance and needs a worker limit — unless it is marked **Managed by
  Aixle**. A managed company is never billed, has no Billing tab, starts with
  two workers, and only a platform administrator can change them. Companies
  that were already running with no Stripe customer are marked managed.
- Contribution rule: a pull request with a change a user or an operator can
  notice adds its entry under `[Unreleased]` in the same pull request. The
  pull-request template asks for it, and `CLAUDE.md` spells it out for agents.

### Fixed
- **Docs**: the GitHub star count in the docs header is the repository's real
  one instead of a fixed number.
- **Docs**: the navigation menu on a phone lists the docs pages again; it
  opened empty.
- **Integrations**: agents get the Slack/Teams message tools (`chat_post_message`
  and the rest) and the Azure DevOps pull request tools again; a rolling
  deploy could leave them switched off, so runs started from Slack could not
  answer in the thread.
- **Sessions & Runs**: a Gemini CLI session no longer counts its tokens more
  than once; usage now comes from one record per model response.
- **Sessions & Runs**: a Codex session stuck on the "Trust this folder?"
  dialog is recognised and stopped with an explanation again, and Codex's
  expired or reused sign-in is reported as one.
- **Sessions & Runs**: an unattended Claude Code step that an MCP server stops
  with a link to open (for example to sign in) or a form to fill in is now
  stopped with an explanation, instead of waiting for a person who never
  comes.
- **Sessions & Runs**: a finished session no longer waits, up to 20 seconds
  under load, while a workflow step's session is being prepared.
- **Aixle Builder**: starting a builder session with an expired agent login
  shows the reason instead of an error page.

## [1.0.0] - 2026-10-08

The first tagged release. The list below is everything Aixle Flow does as of
1.0.0, by product area; later releases list only what changed.

### Added
- **Companies & projects**: companies as separate workspaces; one person can
  belong to several and switch between them from the sidebar.
- **Companies & projects**: projects page with search, per-person favorites,
  project creation and transfer of project ownership.
- **Companies & projects**: light and dark theme.
- **Sign-in & onboarding**: sign-in with password, Google, Microsoft (Entra
  ID), single-use email links or passkeys; the email domain finds the
  workspace.
- **Sign-in & onboarding**: authenticator-app codes, and step-up confirmation
  when a session enters a workspace whose sign-in rules it does not yet meet.
- **Sign-in & onboarding**: email invitations that can be accepted, declined
  or used to create an account, with reminders.
- **Sign-in & onboarding**: two-step onboarding — role and agent output
  language, then connecting an agent runtime; viewers get a short tour.
- **Sign-in & onboarding**: hosted only — self-service workspace signup
  confirmed by email, and a How it works page with pricing and an ROI
  calculator.
- **Sign-in & onboarding**: public landing page, privacy policy and terms of
  service.
- **Profile**: agent runtimes Claude Code, Cursor CLI, Codex, Gemini CLI,
  Antigravity CLI, Grok and Kiro CLI, each connected per company through its
  own login in an in-page terminal.
- **Profile**: Claude Code on your own Amazon Bedrock account, connected
  through AWS IAM Identity Center, with a health check.
- **Profile**: agent logins stored encrypted, refreshed by the server and
  saved back when a CLI rotates them; a failed refresh sends an email.
- **Profile**: default agent and model; sharing your sessions with project
  members; signing out every other browser.
- **Profile**: companies you belong to, pending invitations, and leaving a
  company with a handover of the projects you own.
- **Profile**: Usage tab — your sessions, tokens and spend, and each vendor's
  quota windows with the time until they reset.
- **Profile**: Security tab — link or remove Google and Microsoft sign-in,
  manage passkeys and authenticator codes, end signed-in devices.
- **Profile**: MCP tab — a personal token that makes Flow an MCP server for
  your own agents (Claude Code, Codex, Cursor), acting with your permissions.
- **Profile**: the personal MCP server's tools cover projects, boards,
  workflows, runs, resources and catalogs, with guide prompts; you choose
  which tools it serves.
- **Overview**: project home with KPI cards and period deltas (tasks,
  sessions, runs, spend, cost per session), run outcomes, tasks per column and
  recent activity.
- **Tasks**: one Kanban board per project; each column has a purpose the agent
  receives; columns can be added, renamed, reordered, removed and collapsed.
- **Tasks**: board templates on an empty board: Simple Kanban, Dev Team and
  Full SDLC.
- **Tasks**: cards with a Markdown description, type, priority, assignee,
  tags, parent epic, subtasks, comments, attachments and a stable `#id`.
- **Tasks**: card drawer with details, latest run, run history, comments
  filterable by people or agents, and the card's time, tokens and spend.
- **Tasks**: search by title or `#id` (`/`), filters by type, assignee and
  tag, archived cards, and saved view presets, personal or shared.
- **Tasks**: `n` creates a card; multi-select moves, archives, deletes or sets
  priority, assignee or tags on many cards at once.
- **Tasks**: board activity feed, per-card movement history, and live updates
  for everyone on the board.
- **Tasks**: a column bound to a workflow starts a run when a card enters it,
  or offers Run workflow on the card; cooldown and Retry run.
- **Workflows**: workflows as graphs of sessions (steps); sessions that do not
  depend on each other run in parallel, each in its own container.
- **Workflows**: per session — instructions, persona, required runtime,
  preferred model, resources, inputs, outputs, dependencies and an optional
  BMAD Method install.
- **Workflows**: on failure fail, retry (with a limit) or skip; skip never, if
  outputs exist, or manually; human approval; sub-steps the agent checks off.
- **Workflows**: workflow-wide tools, skills, connectors, assets and
  repositories, optionally inheriting every project resource.
- **Workflows**: declared input and output files (globs allowed); a session
  receives the outputs of every session it runs after.
- **Workflows**: `@` references in instructions to assets, outputs, sessions,
  connectors, tools, skills and config items, checked as you type; a run
  certain to fail does not start.
- **Workflows**: edits kept until Save; each Save is a numbered version with
  history, diff and revert; a Save over a newer version is refused.
- **Workflows**: archive and restore, duplicate, publish to the Workflow
  Catalog, and run by hand with chosen input files.
- **Triggers & gates**: Triggers page with every trigger in the project,
  filterable by source and workflow; add, edit, switch off, delete.
- **Triggers & gates**: triggers on a task entering a column, a schedule (cron
  with time zone), a Slack or Teams message, an incoming webhook, or a task
  tracker event.
- **Triggers & gates**: off-board triggers choose whether a run gets a card
  (none, existing, create, find or create) and run as the trigger's creator.
- **Triggers & gates**: event filters, a cooldown, and de-duplication so a
  re-delivered event never starts a second run.
- **Triggers & gates**: per-project incoming webhooks verified by HMAC
  SHA-256, a shared token, a Slack signature, or nothing.
- **Triggers & gates**: CI gates hold a card on GitHub checks or Actions,
  GitLab pipelines, or Azure DevOps builds and PR policies; a step can also
  wait for a person.
- **Triggers & gates**: gates re-check the provider when a webhook is missed
  and go stale after a time limit.
- **Triggers & gates**: runs report back to their source — a status card in
  the chat thread, or a comment on the tracker issue when a run fails.
- **Sessions & Runs**: one list of workflow runs and standalone sessions, with
  filters and search.
- **Sessions & Runs**: standalone sessions with a runtime, model, persona,
  prompt, resources and interactive or automatic mode; restart from a
  finished session.
- **Sessions & Runs**: live terminal in the browser, an embedded VS Code
  editor for the session's owner, and log replay of finished sessions.
- **Sessions & Runs**: run page with steps in order, parallel steps side by
  side, approve and continue, retry, skip with a reason, and cancel.
- **Sessions & Runs**: per-session tokens and cost, secrets redacted from
  logs, failed repository clones named, and the workflow version each session
  used.
- **Sessions & Runs**: session queues — sessions wait in order for a free
  worker and say whether they wait for a slot, for capacity, or are starting.
- **Sessions & Runs**: run outputs can be downloaded, promoted to project
  assets, or reviewed in bulk to keep or dismiss.
- **Assets**: project files in nested folders — upload, rename, move,
  drag-and-drop, delete, search, and a flat All files view.
- **Assets**: multi-select move and delete, version history per file, and
  files from Slack and Teams messages saved into folders.
- **Assets**: public share links that open a file in a sandboxed viewer and
  can be revoked; agents can create them too.
- **Agents**: personas (title, persona, communication style, principles) that
  run on any runtime; version history, diff, revert and archive.
- **Wrappers**: custom tools run in a container image you choose, with files
  edited in the app; attached to workflows or sessions; versioned and
  archivable.
- **Skills**: catalog mirrored from skills.sh with install counts and security
  audit ratings; a high or critical rating asks for confirmation.
- **Skills**: hand-written skills from a SKILL.md form; installs keep a copy of
  the files; version history, diff, revert and archive.
- **Connectors**: MCP servers over HTTP, SSE or stdio, from a catalog mirrored
  from the official MCP registry or added by hand.
- **Connectors**: header and env values can reference secrets; values are never
  shown, and are cleared when the server's address changes.
- **Connectors**: OAuth 2.1 servers with discovery, automatic or manual client
  registration, shared or per-user credentials, and an email when refresh
  fails.
- **Connectors**: a changed tool list must be accepted before use; catalog
  connectors update in place; packages are pinned to exact versions.
- **Connectors**: version history, diff and revert that never store secrets;
  archive and restore.
- **Connectors**: a built-in `aixle-tools` server in every session — board,
  gates, sub-steps, assets, secrets, other sessions' status, finish or fail.
- **Repositories**: GitHub, GitLab and Azure DevOps repositories with a source
  branch, and public GitHub and GitLab repositories with no integration.
- **Repositories**: clones carry every branch and full history; `git` and `gh`
  get a short-lived token for one repository on each call.
- **Trackers**: GitHub Projects, Azure Boards, Jira, Linear and YouTrack as the
  project's trackers — primary or read-only, detach, and a board column per
  tracker state.
- **Trackers**: agent tools to search, read, create, update, move, assign and
  comment on issues, and link them to board tasks.
- **Integrations**: GitHub through the GitHub App or a personal access token,
  with CI gate webhooks and Test connection.
- **Integrations**: GitLab, self-managed included, through a personal access
  token, with pipeline hooks for CI gates.
- **Integrations**: Azure DevOps through Sign in with Microsoft or an admin
  token — repositories, pull request and build tools, Azure Boards, Service
  Hooks set up automatically.
- **Integrations**: Jira Cloud (Atlassian app or service account), Linear
  (Linear app or API key) and YouTrack Cloud or self-hosted (the Aixle Flow
  YouTrack app).
- **Integrations**: Slack — one or more workspaces, @mention triggers, the Run
  workflow message action, `/aixle run` and `/aixle status`, account linking,
  incoming files.
- **Integrations**: Microsoft Teams — approval link for a Microsoft 365 admin,
  channel and chat triggers, `/run` and `/status`, files both ways.
- **Integrations**: chat tools to post (Markdown, Slack blocks, files), read
  threads, and edit or delete messages in Slack and Teams.
- **Integrations**: Coder — agents take remote workspaces from a pool, clone a
  repository onto one, run commands over SSH and release it.
- **Secrets & Variables**: project secrets and variables, encrypted at rest and
  attached to sessions by name; values stay masked and each delivery is
  logged.
- **Members**: project members picked from the company, with an owner badge
  and removal after confirmation.
- **Analytics**: project analytics by period, scope and person — cost and
  tokens, per-runtime activity, per-workflow cost, sources, durations and an
  activity heatmap.
- **Settings**: project name, description, artifacts language (11 languages),
  reserved workers, archive and delete.
- **Aixle Builder**: describe a process in plain language; an agent acting as
  you creates workflows, steps, triggers, board columns, agents, skills and
  connectors.
- **Aixle Builder**: live terminal and activity feed, workflow checks and test
  runs, Workflows and Board tabs, and past sessions that can be resumed.
- **Templates**: public template catalog (projects, workflows, boards, agents,
  skills, connectors) from maintainer-approved publishers.
- **Templates**: install shows what is created, reused or in conflict, asks
  for settings, and ends on a setup checklist; triggers start switched off.
- **Templates**: publishing as a pull request to AixleHQ/flow-templates through
  the personal MCP server's `publish_template` prompt.
- **Workflow Catalog**: company catalog of published workflows with their
  publisher, search, and Copy & Configure into a project.
- **Company analytics**: admin view across projects — summary, cost and
  tokens, per-runtime activity, per-project breakdown and session sources.
- **Company sessions**: admin list of every session and run in the company,
  with artifact review.
- **Company assets**: company files and folders for admins, shown read-only
  inside each project's Assets.
- **Company members**: member list with search, invitations with a role
  (Admin, Employee, Viewer), resend, role changes and removal, with emails for
  each.
- **Company members**: member profile with a colleague's usage and the
  sessions they share.
- **Company settings**: name, branding (logo and colors) and the number of
  workers (concurrent sessions).
- **Company settings**: Access — the sign-in methods the workspace accepts,
  refusing changes that would lock a member out; per-company OpenID Connect
  connections (Okta, Entra, Ping and others), enabled after a test sign-in.
- **Company settings**: domain verification by DNS TXT record, so people from
  the domain can join automatically; SCIM 2.0 directory sync.
- **Company settings**: hosted billing through Stripe — free worker-hours, a
  balance banner, card checkout, cancel and resume, paying a failed invoice.
- **Docs**: documentation portal at `/docs` with search, user guide,
  integration setup and operator reference.
- Deployment modes: self-hosted (nothing metered), hosted (Stripe billing) and
  AWS Marketplace (hourly worker metering, split per company).
- Docker Compose stack (web, worker, PostgreSQL, Redis, Temporal, Traefik,
  OTLP ingest); `make setup` and `make up` start it.
- Agent sessions as Docker containers or Kubernetes pods in per-project
  namespaces; terminals and editors proxied through Traefik.
- Durable runs on Temporal that survive restarts; board-triggered runs are
  delivered at least once and never start twice.
- Company session capacity, project reservations and a queue health page in
  the admin panel.
- Platform admin panel: impersonation, restore, sign out everywhere and
  permanent delete of users; company capacity; a record browser; catalog
  syncs.
- OpenAPI explorer at `/api-docs` behind HTTP Basic auth.
- Sentry for web, frontend and worker; agent token and cost telemetry through
  OTLP ingest; S3-compatible storage; SMTP mail.
- Versioned releases: a `vX.Y.Z` tag publishes every image to
  `ghcr.io/aixlehq` as `X.Y.Z` (and `X.Y`, `X`, `latest` for a stable
  release), and web `X.Y.Z` launches agent images `X.Y.Z`.
- Agent runtimes and their CLI pins declared once, in
  `config/agent_runtimes.json`, with a weekly canary that reports pins behind
  the vendors' newest releases.
- Apache License 2.0, `NOTICE` attribution file, trademark policy
  (`TRADEMARK.md`) and third-party license inventory
  (`THIRD-PARTY-LICENSES.md`, `NOTICES.md`).
- Contributor model: individual and corporate Contributor License Agreements
  (`CLA.md`, `CLA-CORPORATE.md`) and Developer Certificate of Origin (`DCO`)
  sign-off, documented in `CONTRIBUTING.md`.
- Open-source documentation: README, ROADMAP, quickstart, user guide and
  reference.
- Community health files: Code of Conduct, Security Policy, Governance, issue
  and pull-request templates, CODEOWNERS, and this changelog.

### Changed
For deployments that ran a build from before this release:
- A release's web image launches the agent images of its own version
  (`AGENT_IMAGE_TAG` defaults to it) instead of `latest`; setting
  `AGENT_IMAGE_TAG` still overrides it. Images are no longer published from
  the `main-images` branch.
- Agent runtime images are derived from `AGENT_IMAGE_PREFIX` +
  `AGENT_IMAGE_TAG`; the per-runtime `AGENT_IMAGE_*` variables remain as
  overrides.
- Agent Dockerfiles take their CLI pin as a required `CLI_VERSION` build arg;
  `make build-agents` passes it from `config/agent_runtimes.json`.
- Every deployment input is declared in `config/settings.yml` and documented
  in `docs/reference/configuration.md`.
- The Active Record pool follows Puma's `RAILS_MAX_THREADS` default (10)
  instead of 8 connections.

### Removed
For deployments that ran a build from before this release:
- Configuration nothing read: `AUTHOR_NAME`, `AUTHOR_EMAIL`, `RAILS_PORT`,
  `TEMPORAL_UI_URL`, `REDIS_UI_URL`, `TRAEFIK_DASHBOARD_URL`,
  `TRAEFIK_CORS_ORIGINS`, `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`, `CODER_DEFAULT_TEMPLATE`,
  `CODER_MACHINE_PREFIX`, `MAX_FILE_SIZE`, `ENVIRONMENT`. Setting them now has
  no effect; they can be dropped from ConfigMaps, compose files and CI build
  args.

[Unreleased]: https://github.com/AixleHQ/flow/compare/v1.3.0...develop
[1.3.0]: https://github.com/AixleHQ/flow/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/AixleHQ/flow/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/AixleHQ/flow/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/AixleHQ/flow/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/AixleHQ/flow/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/AixleHQ/flow/releases/tag/v1.0.0
