---
title: 'Session observability and control over the personal MCP'
type: 'feature'
created: '2026-08-10'
status: 'done'
baseline_commit: '6875f465'
review_loop_iteration: 0
context:
  - '{project-root}/docs/research/technical-agent-session-log-access-and-control-research-2026-08-10.md'
  - '{project-root}/docs/testing.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** An agent (or a person driving one) has no way to see what another agent session is doing
while it runs. `SessionLog` rows only exist after the container's cleanup phase, and the one serving
endpoint (`Api::V1::TerminalSessionsController#terminal_log`) deliberately 404s for anything not
`finished`/`failed`. There is likewise no session tool of any kind on the personal MCP: an agent cannot
list sessions, cannot tell a wedged session from a working one, and cannot stop or re-run one — even
though every underlying service call already exists and is used by the web UI.

**Approach:** Add four personal-MCP tools over the existing seams — `list_sessions`, `get_session_log`,
`stop_session`, `trigger_task_workflow` — plus the one shared reachability scope they and the existing
controller both need. Live log reads reuse the proven `runtime.exec!` + `tmux capture-pane` path from
`Activities::Workflow::ScanQuotaErrorsActivity`; finished sessions fall back to the stored
`terminal_output.log`. Stop and re-trigger route exclusively through `SessionService`,
`WorkflowService` and `TaskService`, never through model transitions.

## Boundaries & Constraints

**Always:**
- Route every lifecycle change through `SessionService.finish` / `SessionService.fail_session` /
  `WorkflowService.cancel` / `TaskService.trigger_workflow`. Never `session.fail!`, never
  `session.update!` on state — a hand-rolled transition leaks the pod, Service, IngressRoute and
  Middlewares (see `app/services/session_service.rb:66-85`).
- Gate reads with a single reachability rule: the user's own sessions, or sessions in projects reachable
  through an active membership, **and** `TerminalSession#visible_to?(user)`. Extract it once as
  `TerminalSession.readable_by(user)` and make `Api::V1::TerminalSessionsController#find_readable_session`
  use it, so the tool and the controller cannot drift.
- Answer "not reachable" as not-found, never as forbidden — a session the owner keeps private must be
  indistinguishable from one that does not exist.
- Return log content **unredacted**: no secret filtering, no truncation of information beyond the
  documented byte/line caps. (Product decision, 2026-08-10.)
- Cap what a single call can return (lines and bytes) so a polling agent cannot pull an unbounded blob
  through the MCP transport.
- A live read must distinguish "the pod is gone" from "the command failed": use `exec!` and rescue
  `ContainerRuntime::ContainerUnreachableError` explicitly.
- Tests use the blessed container seam — `stub_container_runtime` + `ContainerRuntime::FakeRuntime`
  (`docs/testing.md` §4). Extend the fake's command router rather than stubbing `exec` per test.

**Ask First:** Redacting or masking log content. Streaming/websocket delivery. A `restart_session`
clone path for standalone agent sessions (needs a new `SessionService.clone_and_start`). Changing what
the container captures, or adding a second log. Raising the 2 MB stored-log tail cap.

**Never:** Do not add a Kubernetes `pods/log` dependency — the app's RBAC grants `pods`, `pods/exec`,
`services` only. Do not expose `auth_setup` sessions (they are owner-only by
`visible_to?` and must stay so). Do not let a read-only (viewer) member stop a session or trigger a
workflow. Do not create new Temporal workflows or schedules. Never attribute a launched run to the
caller just because the caller authorized it — see the attribution rule below.

**Attribution (added 2026-08-10, after the first cut shipped the bug):** authorization and ownership are
separate questions. A personal token authorizes as its owner, but `run.user` is what the container
*spends* — `SessionService.create_for_workflow_step` reads it to pick the agent credential, the runtime
and the model. Ownership therefore belongs to the **task**, and the rule lives in **one** place,
`TaskService#run_owner_for`: the assignee, falling back to whoever asked, skipping a candidate with no
active membership in the company or with the viewer role. Every entry point inherits it — the card's Run
button, this tool, and a column auto-trigger — and `requested_by_id` is recorded in the trigger event so
"who asked" is never lost. `trigger_task_workflow` reads the resulting account back off the run into
`runs_as` rather than predicting it, so there is no second copy of the rule to drift.

## I/O & Edge-Case Matrix

### `list_sessions`

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Default listing | no params | user's reachable, visible sessions, newest first, default 25 (cap 100) | — |
| Project filter | `project_id` | only that project's sessions | unreachable project → "Project N not found" |
| State filter | `state: active\|finished\|failed\|all` | `active` = `not_started`/`running`/`ready`/`finishing` | unknown value → in-band error listing the allowed values |
| Owner hides active sessions | another user's running session, `share_active_sessions? == false` | row absent | — |
| `auth_setup` session of another user | — | row absent | — |

### `get_session_log`

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Running session | state `running`/`ready`, `container_id` present | `source: "live"`, tail from `tmux capture-pane`, `last_output_at`, `idle_seconds` | — |
| Finished session | state `finished`/`failed` | `source: "stored"`, tail of `terminal_output.log`, `truncated` flag when > 2 MB | no log row → `source: "none"`, empty text, still returns session metadata |
| Pod already gone | `exec!` raises `ContainerUnreachableError` | `source: "unreachable"` + the session's own state/error, exit code 0 | never a bare "tool execution failed" |
| tmux not up yet | exec exits non-zero | empty text with `source: "live"`, `note` explaining the container is not ready | — |
| Session not reachable | other company / not visible | in-band error "Session N not found" | never 403-equivalent wording |
| Quota exhaustion in the tail | text matches `QuotaErrorDetector` | `quota_error: { provider:, message: }` | detector failure is non-fatal |
| Huge `lines` | `lines: 100000` | clamped to `MAX_LINES` | — |

### `stop_session`

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Graceful stop | active session, `force` unset | `SessionService.finish`; returns new state | `TerminalSession::InvalidStateError` → in-band error |
| Forced stop | `force: true` | `SessionService.fail_session` with the given reason | — |
| Already finished | state `finished`/`failed` | in-band error naming the current state, no transition | — |
| Viewer member | read-only membership | in-band error "not allowed" | — |
| Visible but not owned | another member's session the user may view | allowed (product decision 2026-08-10) | — |

### `trigger_task_workflow`

| Scenario | Input / State | Expected Output | Error Handling |
|---|---|---|---|
| Manual/auto binding, no active run | — | new `WorkflowRun` id + state, and `runs_as` naming the account it is attributed to | — |
| Attribution | any trigger | `run.user` = `task.assignee`, else the caller — skipping a candidate with no active membership or the viewer role (`TaskService#run_owner_for`). Authorization stays the caller's; `runs_as` reports the resulting account. | — |
| Poisoned history | task already has a run owned by the wrong account | `force` retrigger does NOT inherit that owner — a previous run's user is never a fallback, or the repair reproduces the bug | — |
| Active run present, `force` unset | run `pending`/`running`/`paused` | in-band error naming the blocking run id | — |
| Active run present, `force: true` | — | cancels that run (`WorkflowService.cancel`, which tears the container down through the cleanup phase), then triggers; returns `cancelled_run_id` + new `run_id` | cancel failure → error, no trigger |
| Column has no binding | — | in-band error "No workflow binding on current column" | — |
| Viewer member | read-only membership | in-band error "not allowed" | — |

</frozen-after-approval>

## Code Map

**New**

- `app/services/personal_tools/list_sessions.rb`
- `app/services/personal_tools/get_session_log.rb`
- `app/services/personal_tools/stop_session.rb`
- `app/services/personal_tools/trigger_task_workflow.rb`
- `app/services/sessions/live_log_reader.rb` — the container-side read (capture-pane tail + log mtime),
  isolated so both the tool and any future caller share one command contract
- `test/services/personal_tools/{list_sessions,get_session_log,stop_session,trigger_task_workflow}_test.rb`

**Changed**

- `app/models/terminal_session.rb` — add `scope :readable_by` (reachability) and a `visible_to?`-filtered
  helper for callers that need the second half applied per row
- `app/controllers/api/v1/terminal_sessions_controller.rb:148` — `find_readable_session` uses the new scope
- `app/services/tools/personal_mcp_guides.rb` — short "watch and unstick a run" section documenting the
  cancel-then-trigger sequence
- `test/support/fakes/fake_runtime.rb` — router entries for `tmux capture-pane` (tail of the virtual
  `/tmp/terminal_output.log`) and `stat -c %Y`, plus a knob to make the pane read fail

## Tasks

1. `TerminalSession.readable_by(user)` + controller switched onto it; regression test that the
   controller's visibility behaviour is unchanged.
2. `Sessions::LiveLogReader` — `#tail(lines:)` → `{ text:, last_output_at:, status: }` with
   `:ok | :unreachable | :not_ready`; `FakeRuntime` router extended to back it.
3. `list_sessions`.
4. `get_session_log` (live + stored + quota verdict + idle seconds).
5. `stop_session`.
6. `trigger_task_workflow` (+ `force`).
7. `PersonalMCPGuides` section; research doc cross-reference.
8. `docker compose exec -T web make check_all` green; PR against `develop` in `AixleHQ/flow`.

## Verification

- Unit tests per tool covering every matrix row above, with the container behind
  `stub_container_runtime`.
- Authorization tests: non-member, viewer, and a member who may view but does not own the session.
- `TerminalSession.readable_by` proven equivalent to the controller's previous inline scope
  (existing `test/integration/api/v1/terminal_sessions_log_visibility_test.rb` must stay green).
- Registry test: the four tools are discoverable with `audience :user` and no duplicate names.
- Full suite: `docker compose exec -T web make check_all`.

## Spec Change Log

- **2026-08-17 — "return log content unredacted" narrowed.** The Boundaries rule above ("no secret
  filtering") and its matching *Ask First* entry are renegotiated by
  [spec-session-config-item-access.md](./spec-session-config-item-access.md): values of `secret`
  `ConfigItem`s **attached to the session** are redacted to a fingerprint before a log leaves the
  process, including through `get_session_log`. The set is known and enumerable — this is not a
  heuristic scan for secret-looking text, and everything else in a log is still returned verbatim.
