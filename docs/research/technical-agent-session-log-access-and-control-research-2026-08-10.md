# Agent session logs: infrastructure retention, live log access over the personal MCP, and session stop/re-trigger

**Date:** 2026-08-10
**Status:** research — no implementation
**Scope:** three related asks about `TerminalSession` observability and control

1. Agent logs should be retained **in the infrastructure**, not only in S3.
2. The **personal MCP** should expose a tool that returns the latest logs of a session, so an agent can
   check whether another agent is stuck.
3. The personal MCP should be able to **stop a session and trigger it again**, equivalent to pressing the
   button on a board task card.

---

## 1. As-built: where agent output goes today

### 1.1 Capture inside the container

`docker/base/entrypoint.sh` starts one tmux session named `agent` and pipes its pane twice:

```bash
tmux -u new -d -s agent bash
tmux pipe-pane -t agent "tee -a /tmp/terminal_output.log > /proc/1/fd/1"
tmux send-keys -t agent "$TTYD_CMD" Enter
ttyd -W -p "$TTYD_PORT" tmux -u attach -t agent &
```

Consequences that matter for all three asks:

- `/tmp/terminal_output.log` holds the **raw PTY byte stream with ANSI**, growing live from agent launch.
- The same bytes go to `/proc/1/fd/1` — PID 1's stdout — i.e. **the container's stdout**. Anything that
  collects container stdout already sees the full agent terminal.
- tmux allows only one `pipe-pane` per pane, which is why both sinks are chained through one `tee`.
- ttyd runs writable (`-W`); the live view is an interactive attach, not a log feed.

Additional per-session artifacts:

- `/var/log/mitm/http.log` — MITM proxy log of `api.anthropic.com` traffic
  (`Agents::ClaudeCodeAdapter#session_log_paths:44`, `default_env_vars:703`).
- OTLP metrics (tokens/cost) exported to `Settings.otel.endpoint`, ingested by
  `ClaudeCodeAdapter#ingest_usage:735` into `UsageStatistic`.

### 1.2 Collection into the app (end of session only)

`ContainerStrategies::AgentSessionStrategy#before_cleanup:95` runs in the container workflow's `cleanup`
phase and is the **only** path that persists logs:

- `collect_logs:175` — reads each `adapter.session_log_paths` file via `read_file_from_container`
  → one `SessionLog` per file (Claude: `http.log`).
- `collect_terminal_output:152` — reads `/tmp/terminal_output.log` → `SessionLog` named
  `terminal_output.log`.
- `SessionLogUploader` writes to Shrine `store` under `sessions/<id>/logs/<file>`; in production that is
  S3 (`config/initializers/shrine.rb#other_setup`), on dev the local filesystem, in test memory.
- Uploader cap: 1 GB per log.

`WorkflowStepStrategy` does the same for `workflow_step` sessions.

**Implication:** while a session runs, the platform database holds *no* log. Everything lives in the pod,
and lands in S3 only at cleanup. A session that dies with its node (bare pods, `restartPolicy: Never`)
never reaches cleanup — see `Activities::Session::ScanDeadContainersActivity`, which exists precisely
because a node OOM stranded ten sessions — and its terminal output is then lost entirely.

### 1.3 Serving logs to users

`Api::V1::TerminalSessionsController#terminal_log:71`:

- gated on `state.in?(%w[finished failed])` — **running sessions return 404 by design**;
- serves only the tail (`MAX_LOG_BYTES = 2 MB`) with an `X-Log-Truncated` header;
- authorization is `find_readable_session:148` — owner, or a project the user can reach, and then
  `TerminalSession#visible_to?` (owner sharing preferences: `share_active_sessions?` /
  `share_completed_sessions?`; `workflow_step` sessions are always visible, `auth_setup` never).

Rendered by the frontend in xterm.js (`docs/implementation-artifacts/spec-session-terminal-replay.md`).

### 1.4 The one existing live-read seam

`Activities::Workflow::ScanQuotaErrorsActivity#live_terminal_output:62` already reads a **running**
session's terminal:

```ruby
runtime.exec!(container, ["sh", "-c", "tmux capture-pane -t agent -p -S -1000 2>/dev/null || true"], ...)
```

with `exec!` so a vanished pod raises `ContainerRuntime::ContainerUnreachableError` instead of looking
like a failed command. This is the blessed pattern to copy for a live-log MCP tool: it works on both
runtimes (`DockerRuntime#exec`, `KubernetesRuntime#exec:85` via the pod exec websocket), and the app's
Kubernetes RBAC already grants `pods/exec` (`kube/helmfile/values/aixle-app/common.yaml:37`:
`["pods", "pods/exec", "services"]`).

Note what that RBAC does **not** include: `pods/log`. Reading pod logs through the Kubernetes API from
the app would need an RBAC change; exec would not.

### 1.5 Existing watchdogs (what "stuck" already means)

| Watchdog | Detects | Action |
|---|---|---|
| `ScanDeadContainersActivity` | pod `missing`/`terminated` while session `running`/`ready`, confirmed twice 2 min apart, min age 2 min | `SessionService.fail_session` |
| `CleanupStaleActivity` | `running` > 30 min, `ready` > 25 h, `finishing` > 10 min | full cleanup → `finished`, or `failed` |
| `ScanQuotaErrorsActivity` | quota/billing patterns in live terminal output of `workflow_step` sessions | `SessionService.fail_session` |

None of them detects an agent that is **alive but idle** (waiting on a prompt, spinning on a tool, hung on
a network call). That is exactly the gap ask #2 names.

---

## 2. Ask #1 — logs in the infrastructure, not only S3

### 2.1 Finding: the infrastructure already collects them — verified against staging

`~/projects/dualboot/aixle-infra` runs a Loki + Grafana Alloy stack, `observability.enabled: true` in
**both** `staging` and `prod` environments.

Alloy (`kube/helmfile/values/observability/common/alloy.yaml.gotmpl`) discovers `role = "pod"`
**cluster-wide, with no namespace filter**, relabels `namespace` / `pod` / `container` / `app` / `node`,
drops health-probe and AWS-CNI noise, and writes to `loki.monitoring.svc.cluster.local:3100`.

Agent session pods are ordinary pods in per-project / per-user namespaces:

- namespace: `aixle-project-<project_id>`, else `aixle-user-<user_id>`, else `aixle`
  (`KubernetesRuntime#namespace_for:977`);
- pod name: `terminal-<route_token>`; labels `app=aixle-runtime`,
  `aixle-container=<pod_name>` (`session_labels:966`, `RUNTIME_APP_LABEL:24`).

Because `pipe-pane` tees to `/proc/1/fd/1`, the whole agent terminal stream is on the pod's stdout, and
Alloy is tailing it into Loki. **This was confirmed empirically against the staging cluster on
2026-08-10** (queries in §9):

- `app` label values over 30 days include `aixle-runtime`; `namespace` values include
  `aixle-staging-project-3`. Both are absent from a 6-hour window only because staging has been idle.
- A sample line stream carries the expected labels:
  `{app="aixle-runtime", namespace="aixle-staging-project-3", pod="terminal-<route_token>",
  container="main", cluster="aixle-staging", instance="<ns>/<pod>:main"}`.
- The log bodies are the **raw ANSI PTY stream**, including the Claude Code TUI splash
  (`[?1049h[2J…✳ Claude Code … v2.1.216 … Welcome back …`), through to
  `received signal: SIGTERM (15), exiting...` at teardown.

So ask #1 is a *labelling, retention and secrets* problem, not a missing pipeline.

### 2.2 What is wrong with relying on it as-is

Measured on staging (30-day window, 4 agent pods — the cluster has been mostly idle):

| Measurement | Value |
|---|---|
| Total agent-pod log volume, 30 d | 0.05 MiB across 4 pods |
| Busiest session | 3 active minutes, 48.5 KiB total, **peak 47.3 KiB/min**, median 1.0 KiB/min |
| Whole-cluster ingest, 24 h | 644 MiB (`monitoring` 402 MiB, `aixle-staging` 88 MiB, `arc-system` 86 MiB, rest smaller) |
| Loki PVC | `storage-loki-0`, 20 Gi gp3, single replica, filesystem store |

| Risk | Detail |
|---|---|
| **Volume vs. Loki capacity** | Lower than feared. Peak measured agent output is ~47 KiB/min ≈ 2.8 MiB/h per active session, against an `ingestion_rate_mb: 4` (≈240 MiB/**min**) limit — saturating it would take thousands of concurrent agents. The real constraint is **storage**: the cluster already writes ~644 MiB/day, which over the 720 h retention is ~19 GiB against a 20 Gi PVC *before* agents are counted. Actual PVC utilisation was not measured (needs Prometheus access); it should be, because agent traffic lands on a disk that may already be close to full. Prod volume is unmeasured — the prod cluster reads were not permitted in this session. |
| **Retention** | `retention_period: 720h` (30 days). Fine for ops, not a product-facing archive. S3 stays the system of record. |
| **No tenant/session labels** | Loki knows `namespace` + `pod`. Mapping back to a session needs `route_token` → `TerminalSession`, which only the app can do. There is no `session_id`/`company_id`/`project_id` label. |
| **Secrets** | The terminal stream is unredacted. Auth flows, `env` dumps, an agent `cat`-ing a credentials file, MCP bearer tokens — all land verbatim in a cluster-wide log store queried by anyone with Grafana access. S3 has the same problem today, but Loki widens the audience. |
| **Durability of the product artifact** | Loki is not a substitute for `SessionLog`: it has no per-session ACL, and a lost node still loses the *live* tail between the last Alloy scrape and the death — small, but the bigger loss is that no `SessionLog` row is created at all for a session that never reaches cleanup. |
| **Docker runtime / dev** | Nothing collects container stdout locally; anything built on Loki is k8s-only. |

### 2.3 Options

**A. Lean on Alloy/Loki, harden it.** Add pod labels (`aixle.com/session-id`, `project-id`, `company-id`)
in `KubernetesRuntime#session_labels` and matching Alloy relabel rules, so LogQL can select a session
directly. Optionally add an Alloy `stage.drop` for pure redraw noise, and a per-namespace rate limit so
agent spam cannot starve platform logs. Cheap, no app changes beyond labels.
*Does not* fix secrets, ACLs, or the missing `SessionLog` for dead sessions.

**B. Periodic checkpoint into `SessionLog` (recommended alongside A).** A Temporal sweep (or a phase in
the container workflow) tails `/tmp/terminal_output.log` every N minutes for active sessions and appends
to a rolling `SessionLog` — or writes `terminal_output.partial.log`, replaced at cleanup. This makes the
product-facing log survive a dead node, gives the MCP tool a cheap source that does not exec into a pod
on every call, and keeps working on the Docker runtime. Cost: extra exec + S3 writes per active session
per interval; needs an offset/`byteslice` scheme so each checkpoint ships only the delta.

**C. OTLP logs export.** `Settings.otel.logs_endpoint` already exists (`config/settings.yml:83`) and is
unused for agent output. Would mean a log shipper in the container (or Claude Code's own OTLP logs
exporter) pointed at the collector. Adds a second pipeline with the same secret-exposure problem and no
advantage over A for the terminal stream. **Not recommended** for terminal bytes; it is the right channel
if we ever want *structured* agent events instead of a PTY dump.

**D. Sidecar shipper per agent pod.** Rejected: doubles pod count and memory on nodes already sized at
2 Gi/500 m per agent (see the agent pod sizing work), for what A already gives.

### 2.4 Recommendation

**A + B.** Loki is the ops surface (query by namespace/pod/session label, 30-day window); `SessionLog` in
S3 stays the product surface and becomes crash-resistant via checkpointing. Add a redaction pass at
capture time if the secret exposure is judged unacceptable — that is a separate, larger decision (it
affects the replay UX and cannot be applied retroactively to S3 logs).

---

## 3. Ask #2 — a personal-MCP tool for the latest session logs

### 3.1 What exists on the personal MCP today

`Tools::PersonalMCPRequestHandler` serves every registry definition with `audience :user`
(`Registry.for_audience(:user)`), authenticated by an `amcp_` user token; handlers subclass
`PersonalTools::Base` and must authorize through the **same Pundit policies as the UI**
(`PersonalTools::Base#authorize!:34`). Tool names are `Class.name.demodulize.underscore`, surfaced to
agents as `mcp__flow__<name>`.

**There is no session tool at all** — no `list_sessions`, no `get_session`, no log tool. So ask #2 needs
at least two tools: one to find the session, one to read it.

### 3.2 Proposed tools

#### `list_sessions`

| | |
|---|---|
| Params | `project_id` (optional), `state` (optional: `active`/`finished`/`failed`), `limit` |
| Returns | id, state, session_type, agent_type, mode, started_at/ready_at/finished_at, `step_run_id`/`workflow_run_id` from metadata, token/cost totals, `idle_seconds` |
| Scope | `TerminalSession` in the user's active-membership companies, filtered by `visible_to?(user)` |
| Annotations | read-only |

#### `get_session_log`

| | |
|---|---|
| Params | `session_id`, `lines` (default ~200, hard cap), `strip_ansi` (default true), `include_mitm` (default false) |
| Returns | tail text + `{ state, source: live\|stored, truncated, bytes, last_output_at, idle_seconds, error_message }` |
| Source selection | `state ∈ {running, ready}` **and** `container_id` present → live read; otherwise → stored `SessionLog#terminal_output.log` tail (reuse `read_log_tail`, `MAX_LOG_BYTES`) |
| Live read | `runtime.exec!(container, ["sh", "-c", "tail -c <N> /tmp/terminal_output.log"])` or the existing `tmux capture-pane -t agent -p -S -<lines>`; rescue `ContainerUnreachableError` → report `container_unreachable` rather than a generic failure |
| Annotations | read-only |

`capture-pane` returns the rendered screen + scrollback (already de-ANSI'd, aligned to lines) — better for
"is it stuck", and it is the pattern already proven in `ScanQuotaErrorsActivity`. `tail -c` on the raw log
returns bytes an agent then has to strip. **Recommend `capture-pane` as the primary live source**, with the
raw file as a fallback when tmux is gone.

#### Stuck-detection payload (the actual product value)

An agent asking "is it stuck" does not want 200 lines of TUI; it wants a verdict. Derive and return:

- `idle_seconds` — from the pod's `stat -c %Y /tmp/terminal_output.log` (last write), or the delta since
  the last differing `capture-pane` hash if we keep one;
- `last_output_at`, `state`, `error_message`;
- for `workflow_step` sessions: the `StepRun` state and `updated_at` (a frozen `updated_at` is the
  documented symptom in `ScanDeadContainersActivity`);
- optionally a `quota_error` flag by running `QuotaErrorDetector.detect` over the tail — the detector is
  already a pure function over text and is exactly the "why is it wedged" answer for the most common case.

### 3.3 Authorization

The existing `Web::Company::SessionsPolicy` is `admin?`-only for `index/show`, which is the *company-wide
session list*, not the right gate for reading a session you can already reach in the UI. The correct
composition, mirroring `Api::V1::TerminalSessionsController#find_readable_session:148`:

1. session belongs to the user, **or** to a project reachable via an active membership
   (`Project.for_user`);
2. `TerminalSession#visible_to?(user)` — honours the owner's `share_active_sessions?` /
   `share_completed_sessions?` preferences, `auth_setup` stays owner-only, `workflow_step` is always
   visible;
3. 404, never 403, for anything that fails — a private session must be indistinguishable from a
   nonexistent one (established rule at `terminal_sessions_controller.rb:145`).

Do **not** reuse `container_accessible_by?` — that gates an interactive writable shell.

### 3.4 Cost and abuse considerations

- Every live call is a pod exec (websocket upgrade). Cap `lines`, cap returned bytes, and consider a
  short per-session cache (5–10 s) so a polling agent cannot hammer the API server. `ScanQuotaErrorsActivity`
  already showed the failure mode: re-exec'ing against dead pods pinned `worker-ruby` at its HPA ceiling.
- If checkpointing (option B above) ships, `get_session_log` can read the checkpoint for anything older
  than the checkpoint interval and only exec for the freshest tail.
- Redaction: the tail may contain tokens. At minimum, run the same redaction the OAuth work uses for
  `context.log` before returning text to an MCP client.

---

## 4. Ask #3 — stop a session and trigger it again

### 4.1 "Restart" means three different things here

| Session type | How it starts | How to stop it | How to "run it again" |
|---|---|---|---|
| `agent_session` (a person launches an agent) | `SessionService.create_and_start` | `SessionService.finish` (graceful: signals `container_finished`, cleanup collects logs/outputs) or `fail_session` | **No clone path exists.** Would need a new helper that copies agent_type / mode / initial_prompt / requested_model / tools / skills / mcp_servers / repositories / input_assets and calls `create_and_start` |
| `workflow_step` (a workflow step's container) | `SessionService.create_for_workflow_step` | `SessionService.fail_session` — never `session.fail!` alone, or the pod/Service/IngressRoute leak for 23 h (documented at `session_service.rb:66-85`) | `WorkflowService.retry_step(step_run:)` — already exposed as the personal tool `retry_step_run` |
| Board task card | `POST /api/v1/projects/:id/tasks/:task_id/trigger_workflow` → `TaskService.trigger_workflow` | `WorkflowService.cancel(run:)` — already exposed as `cancel_workflow_run` | the same `trigger_workflow` call |

The button the ask refers to is the board card's **"Run workflow"**
(`tasks_controller#trigger_workflow:80`, verified in `BoardPage.test.tsx:962`). Its guards
(`TaskService#trigger_workflow:136`):

- the task's column must carry a `column_workflow_binding` with `trigger_mode ∈ {manual, auto}`;
- **it refuses when the task already has a run in `pending`/`running`/`paused`**;
- it records a `TriggerEngine` manual event and dispatches it, returning the `WorkflowRun`.

So "stop it and press the button again" is genuinely a **two-step sequence**: cancel the active run, then
trigger. A single tool that only triggers will fail with `"Active workflow run already exists for this
task"` in exactly the stuck case the user cares about.

### 4.2 Proposed tools

#### `trigger_task_workflow`

| | |
|---|---|
| Params | `project_id`, `task_id`, `force` (default false) |
| Behaviour | `force: false` → straight `TaskService.trigger_workflow`. `force: true` → `WorkflowService.cancel(run:)` on the active run first, then trigger. |
| Returns | `run_id`, `state`, `workflow_name`, and (when forced) `cancelled_run_id` |
| Policy | the same policy the board controller applies to `trigger_workflow`; viewers must be refused (viewers cannot launch sessions — `terminal_sessions_controller.rb:16`) |
| Annotations | destructive (it can cancel work in flight) |

`WorkflowService.cancel:47` already signals `workflow_cancelled`, cancels active step runs, transitions
the run, and broadcasts the board update — so `force` composes with the existing teardown rather than
inventing one.

**Does cancelling release the container? Yes — traced end to end:**

1. `WorkflowService#cancel_active_step_runs:119` iterates `pending`/`running`/`waiting_input` step runs
   and calls `SessionService.cancel(session: sr.terminal_session)`, then `sr.mark_cancelled!`.
2. `SessionService.cancel:61` calls `TemporalService.cancel_workflow(session.workflow_id)` and then
   `session.fail!`.
3. `Workflows::ContainerWorkflow#run:33` rescues the cancellation
   (`raise unless Temporalio::Error.canceled?(e)`) and calls `run_cleanup_detached:65`, which executes the
   `cleanup` phase activity with a **fresh `Temporalio::Cancellation.new`** — a detached scope, so the
   activity runs even though the workflow itself is cancelled — before re-raising.
4. The `cleanup` phase is the one that runs `before_cleanup` (logs, outputs, usage, credential
   write-back) and `remove_container` (pod, Service, IngressRoute, Middlewares).

So `force`-cancelling does **not** leak a pod, and it still collects the terminal log — which is the
behaviour a "stop and re-run" tool wants.

Two residual notes, neither blocking:

- `SessionService.cancel` uses Temporal **cancellation**, not the `container_finished` **signal** that
  `finish`/`fail_session` use. Both converge on the cleanup phase; the difference is that the cancelled
  workflow ends in a cancelled state rather than completing.
- `cancel_temporal_workflow:231` swallows a failed cancel (logs and returns) while `session.fail!` still
  runs. The session row is then `failed`, which puts it outside the `running`/`ready` scopes of
  `ScanDeadContainersActivity` and `CleanupStaleActivity` — but *inside* the guard set of
  `Activities::Container::SweepOrphanedResourcesActivity` (terminal-state owner + minimum age), which
  runs every 10 minutes and reclaims the pod and its routing objects. Worst case the container also
  self-terminates when the workflow's own 23 h `signal_timeout` expires and its cleanup phase runs.

#### `stop_session`

| | |
|---|---|
| Params | `session_id`, `reason` (optional) |
| Behaviour | `SessionService.finish(session:)` for a graceful stop (logs and outputs are collected — the reason to prefer it); `SessionService.fail_session(session:, error_message: reason)` when the caller wants it marked failed, e.g. to unblock a workflow step |
| Policy | owner, or a non-viewer member of the session's project; never merely "visible" — reading someone's log is a share they opted into, killing their session is not |
| Annotations | destructive |

Rule for the implementation: **always go through `SessionService`**. Both comments in
`session_service.rb` exist because hand-rolled `update! + fail!` leaked Kubernetes objects for a day per
incident.

#### `restart_session` (optional, agent sessions only)

Clone-and-start with the same configuration, returning the new session id, and optionally finishing the
old one first. Needs a new `SessionService.clone_and_start(session:)`; everything it must copy is already
enumerated in `create_and_start`'s `params.slice` and `attach_resolved_resources`. Deferrable — for
`workflow_step` and board-driven work, `retry_step_run` and `trigger_task_workflow` cover the real cases.

---

## 5. Proposed tool surface (summary)

| Tool | Audience | Tags | Read-only | Backed by |
|---|---|---|---|---|
| `list_sessions` | user | `sessions` | yes | scoped `TerminalSession` + `visible_to?` |
| `get_session_log` | user | `sessions` | yes | live `runtime.exec!` / stored `SessionLog` |
| `stop_session` | user | `sessions` | no | `SessionService.finish` / `fail_session` |
| `trigger_task_workflow` | user | `boards`, `workflows` | no | `TaskService.trigger_workflow` (+ `WorkflowService.cancel` when forced) |
| `restart_session` (optional) | user | `sessions` | no | new `SessionService.clone_and_start` |

A new `sessions` tag needs an entry in `Tools::TagCatalog` if these should appear as a picker group.
`PersonalMCPGuides` should gain a short "watching and unsticking a run" section — the guides file is how
agents learn multi-call sequences like cancel-then-trigger.

---

## 6. Phasing

| Phase | Work | Depends on |
|---|---|---|
| **0** | ~~Verify agent pod logs in Loki~~ — **done 2026-08-10, they are there** (§2.1). Remaining: measure the Loki PVC's actual utilisation, and repeat the volume query on prod | — |
| **1** | `list_sessions` + `get_session_log` (live exec + stored fallback, `idle_seconds`, `QuotaErrorDetector` verdict) | — |
| **2** | `stop_session` + `trigger_task_workflow` (with `force`) — the cancel path is confirmed safe (§4.2) | 1 |
| **3** | Session-identifying pod labels + Alloy relabel rules; per-namespace ingest limits | 0 |
| **4** | Checkpointed `SessionLog` for active sessions (survives node death, cheapens `get_session_log`) | 1 |
| **5** | Optional: redaction at capture, `restart_session` clone path | 4 |

Tests follow `docs/testing.md`: personal tools are unit-tested against the registry + policy seams, the
runtime is stubbed at `ContainerRuntime` (never `any_instance`), and the live-read path gets a fake
runtime returning canned `exec!` triples — the pattern `ScanQuotaErrorsActivity`'s tests already use.

---

## 7. Open questions

1. **Secrets in the terminal stream.** Shipping raw PTY output to a cluster-wide Loki widens who can read
   an agent's credentials. Accept, redact at capture, or restrict Grafana access?
2. ~~Does `WorkflowService.cancel` release the step's container?~~ **Resolved** — yes, via
   `SessionService.cancel` → Temporal cancellation → `ContainerWorkflow#run_cleanup_detached`. See §4.2.
3. **Live-read source:** `tmux capture-pane` (rendered, line-aligned, proven) vs. `tail -c` on the raw log
   (exact bytes, needs ANSI stripping). Recommendation is capture-pane; confirm it is adequate for agents
   diffing output between polls.
4. **Polling discipline.** Should `get_session_log` carry a server-side minimum interval per session, or is
   a documented convention in `PersonalMCPGuides` enough?
5. **Cross-user control.** Should a company admin be able to `stop_session` on someone else's session?
   Today `visible_to?` deliberately gives admins no override for *reading*; stopping is a stronger act.
6. **Loki retention (30 d) vs. `SessionLog` (indefinite in S3).** Is a shorter, cheaper S3 lifecycle policy
   wanted once Loki covers the ops window?

---

## 8. Code map

| Concern | Location |
|---|---|
| tmux capture + dual sink | `docker/base/entrypoint.sh:108-129` |
| Log collection at cleanup | `app/services/container_strategies/agent_session_strategy.rb:95,152,175` |
| Log storage | `app/uploaders/session_log_uploader.rb`, `app/models/session_log.rb`, `config/initializers/shrine.rb` |
| Serving finished logs | `app/controllers/api/v1/terminal_sessions_controller.rb:71,112,148` |
| Live terminal read (precedent) | `app/temporal/activities/workflow/scan_quota_errors_activity.rb:62` |
| Session lifecycle | `app/services/session_service.rb:45,61,86,93` |
| Session visibility rules | `app/models/terminal_session.rb:106,128` |
| Watchdogs | `app/temporal/activities/session/{scan_dead_containers,cleanup_stale}_activity.rb` |
| Board card button | `app/controllers/api/v1/projects/board/tasks_controller.rb:80`, `app/services/task_service.rb:136` |
| Run cancel / step retry | `app/services/workflow_service.rb:47,72` |
| Personal MCP | `app/services/tools/personal_mcp_request_handler.rb`, `app/services/personal_tools/base.rb`, `app/services/tools/registry.rb` |
| Existing control tools | `app/services/personal_tools/{cancel_workflow_run,retry_step_run,trigger_workflow}.rb` |
| K8s pod identity | `app/services/container_runtime/kubernetes_runtime.rb:24,85,966,977` |
| Infra log stack | `aixle-infra: kube/helmfile/values/observability/common/{alloy.yaml.gotmpl,loki.yaml}`, `kube/helmfile/values/aixle-app/common.yaml:37` |

---

## 9. Appendix — how §2.1/§2.2 were verified (staging, 2026-08-10)

Loki has no ingress; reach it through a port-forward. `terminal-*` pods live in per-project namespaces,
so all queries select on the `app` label rather than a namespace.

```bash
aws-vault exec terraform@palad -- kubectl --context aixle-staging \
  -n monitoring port-forward svc/loki 3100:3100 &

# Label endpoints default to a 6h window — pass an explicit range or an idle
# cluster looks like it never collected agent logs at all.
S=$(date -u -v-30d +%s)000000000; E=$(date -u +%s)000000000
curl -sG "http://127.0.0.1:3100/loki/api/v1/label/app/values"       --data-urlencode "start=$S" --data-urlencode "end=$E"
curl -sG "http://127.0.0.1:3100/loki/api/v1/label/namespace/values" --data-urlencode "start=$S" --data-urlencode "end=$E"

# Sample the stream (labels + raw ANSI bodies)
curl -sG 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={app="aixle-runtime"}' --data-urlencode "start=$S" --data-urlencode "end=$E" \
  --data-urlencode 'limit=8' --data-urlencode 'direction=backward'

# Per-session volume, and per-minute rate for one session
curl -sG 'http://127.0.0.1:3100/loki/api/v1/query' \
  --data-urlencode 'query=sum by (pod) (bytes_over_time({app="aixle-runtime"}[30d]))'
curl -sG 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query=sum(bytes_over_time({app="aixle-runtime",pod="terminal-<token>"}[1m]))' \
  --data-urlencode 'start=<RFC3339>' --data-urlencode 'end=<RFC3339>' --data-urlencode 'step=60'

# Cluster baseline for comparison
curl -sG 'http://127.0.0.1:3100/loki/api/v1/query' \
  --data-urlencode 'query=sum by (namespace) (bytes_over_time({job="loki.source.kubernetes.pod_logs"}[24h]))'
```

Gotcha: `query_range` with `step=60` over 30 days exceeds Loki's max-points limit and returns an empty
body — narrow the window to the session's own hours before asking for per-minute buckets.

Not verified: Loki PVC utilisation (needs Prometheus/kubelet volume stats), and every prod-side number —
prod cluster reads were declined in this session.
