# Coder pool hardening — design

**Status:** proposed
**Created:** 2026-08-10
**Baseline:** `origin/develop` @ `6e98a7b7`
**Trigger:** field report from agent sessions working Flow project 27 (Collectively) on
2026-08-09 — Coder integration 46 ("Coder (admin)"), `coder.staging.flow.aixle.com`,
template `aws-ec2-spot-v1`. Two cards burned two QA windows each without running a
single check; three more queued behind them. In none of the runs was the product code
in question.

This document covers the platform (`AixleHQ/flow`) side and the infrastructure
(`aixle-infra`) side. It supersedes nothing; it extends the Coder MCP tooling shipped
under task #284 (`Coder::Allocator`, `Coder::LockService`, `Coder::SshRunner`,
`coder_allocate_machine` / `coder_ssh_exec` / `coder_release_machine`).

---

## 1. Observed behaviour

From one QA session:

| # | Allocation | Command | Timeout | Result |
|---|---|---|---|---|
| 1 | `collectively-prod-920a776c` | `export HOME=/root; uptime; docker --version` | 60 s | timed out |
| 2 | released `true`, re-allocated | same workspace | 120 s | timed out |
| 3 | same workspace | `echo alive` | 180 s | timed out |
| 4 | released `true`, re-allocated | same workspace | 120 s | timed out |

A separate session watched the same box sit at `load average: 84.34` and stop answering
`uptime` for roughly 100 minutes.

Pool at the time — 8 workspaces, 5 running, all on `aws-ec2-spot-v1`:

```
collectively-prod-1b5aaa99   Running
collectively-prod-598c5f75   Running
collectively-prod-920a776c   Running   <- the only one ever handed out
collectively-prod-955e3101   Running
collectively-prod-aa9f2995   Running   (amber agent health)
collectively-prod-9ef2e23a   Stopped
aixle-prod-43ff9050          Stopped
aixle-prod-7916ff12          Stopped
```

## 2. Root causes

The field report's headline — "the pool resolves to exactly one workspace" — is a
symptom, not the cause. Reading `app/services/coder/allocator.rb`, the pool resolved
correctly; four independent defects stacked into the observed behaviour.

### RC-1 — allocation never checks health

`Allocator#allocate` (`allocator.rb:33`) sorts candidates by
`latest_build.transition == "start" && latest_build.job.status == "succeeded"` and then
by name, and hands over the first workspace whose lock it can take. Two consequences:

- **Build status is not liveness.** A box whose Terraform build succeeded three days ago
  and has been thrashing ever since still sorts as healthy. `status: "running"` is
  evidence about the *build*, not about the agent, the SSH path, or the load.
- **The Coder agent's own health signal is discarded.** `GET /api/v2/workspaces` already
  returns `latest_build.resources[].agents[].status` (`connected` / `disconnected` /
  `timeout`) and `agents[].health.{healthy,reason}` — the amber indicator visible in the
  UI. `Coder::WorkspaceService#list` passes the whole JSON through; nothing reads it.

### RC-2 — a session that lands on a bad box cannot get off it

Allocation is deterministic: same pool, same sort, same first free entry. `1b5aaa99` and
`598c5f75` sort before `920a776c` and were held by *other* sessions' locks, so `920a776c`
was the first free candidate — and stayed the first free candidate across every
release / re-allocate cycle. `coder_allocate_machine` exposes only `note`; there is no
`exclude`, and no server-side memory that the last hand-out failed. Releasing and
re-allocating is precisely the move a session makes when a box is bad, and it is
guaranteed to return the same box.

### RC-3 — locks expire on acquisition age, not on activity

`Coder::LockService` sets `expires_at = now + ttl` at acquire time and never renews
(`lock_service.rb:47-86`); the default TTL is 60 minutes (`lock_service.rb:126`).
Release happens on the happy path (`coder_release_machine`) or at step teardown
(`IntegrationCleanupService`). A step that dies hard — pod OOM, Temporal timeout,
container kill — leaves the lock in place for up to a full hour, which is why an
8-workspace pool presented as a 1-workspace pool. Conversely, a healthy long-running
session can have its lock expire out from under it mid-gate.

### RC-4 — `coder_ssh_exec` kills the SSH call, not the remote work, and says nothing about it

`docker compose run` is a Docker daemon client; the container it starts is not a child of
the SSH session. When `Coder::SshRunner` hits its deadline it kills the local `coder ssh`
process group (`ssh_runner.rb:143`) and returns:

```ruby
{ exit_code: 124, stdout: "", stderr: "coder ssh: timed out after #{timeout}s", truncated: false }
```

Nothing in that payload says the remote work survived. A session reads it as "the gate
died", re-issues, and now two `check_all` runs share one box. The repo's `flock` does not
save it: `TEST_LOCK` covers only `rails test` and `rails test:system`, so `rubocop`,
`brakeman`, `eslint`, `tsc`, `vitest`, `ruff`, `pytest` and the network audits all start
immediately on top of the first run. That is what produced `load average: 84` on a
4-vCPU box — and RC-1 then kept handing that box out.

Compounding this: the tool's schema advertises `timeout_seconds` "max 600" and
`SshRunner::MAX_TIMEOUT` is 600, but the measured ceiling is ~90–150 s (`sleep 240` with
`timeout_seconds: 330` still timed out). The cap is imposed above our code — MCP client
or the ingress path in front of the MCP server — and is not modelled anywhere. A 15–25
minute gate cannot run in the foreground under any setting the tool offers.

### RC-5 — per-session tuition baked into no image

Each session rediscovers, at cost:

1. `$HOME` is unset in `coder ssh` — every `git` call dies with `fatal: $HOME not set`.
   The template's agent env (`terraform/coder/templates/staging/aws-ec2-spot-v1/main.tf:18`)
   sets only `CODER_ACCESS_URL`.
2. `/root/app` is a `--filter=blob:none` partial clone whose promisor remote has no
   credentials; a fetch spawns a second fetch that hangs on Coder's auth helper. Needs a
   tokenised `remote.origin.url` plus `GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true`.
3. The clone is shallow and single-branch (`+refs/heads/<default>:` only), so feature
   branch refs do not exist locally — every session unshallows and widens the refspec.
4. The repo bind mount is SELinux-labelled while the container runs as uid 100, so a
   runner writing into the repo gets `Errno::EACCES`; `--user root` does not help. This
   one silently changed what a story could deliver, because a code-generation step could
   not write its output.
5. `buildx` is 0.12.1 while compose 5.1.3 requires ≥ 0.17.

**Nothing on the box is provisioned.** The template live in Coder was pulled and
compared against `terraform/coder/templates/staging/aws-ec2-spot-v1` on 2026-08-10: they
are identical, so there is no infrastructure-as-code drift. That is the finding. The
template boots an EC2 spot instance and starts the Coder agent — its `startup_script` is
`set -euxo pipefail` and nothing else. The Packer image
(`terraform/coder/packer/coder-workspace/scripts/bootstrap.sh`) installs docker, compose,
git, rg, jq, make, tmux and a spot-interruption watcher; no buildx (0.12.1 comes in with
the AL2023 `docker` package), no clone, no git configuration, no service start.

Therefore `/root/app`, the eight running containers, and the partial-clone remote are
**sediment from earlier manual sessions** on boxes that are never recycled. Every item in
RC-5 is a workaround for state no one provisions and no one owns — which is exactly why
each session pays for it again.

Latent, separate: `root_volume_size_gb` defaults to 20 while the AMI's snapshot is built
at 30 GiB (`packer/coder-workspace/staging.auto.pkrvars.hcl.example`). EC2 refuses a root
volume smaller than its snapshot, so either the running workspaces were created with an
overridden value or the AMI snapshot is smaller than the example suggests. Verify against
a live instance before trusting the number.

### RC-6 — the workspace runs eight containers when the gate needs three

Allocation hands over a box with the product's full `docker-compose.yml` up: `temporal`,
`temporal-ui`, `web`, `worker`, `db`, `redis`, `python-worker`, `minio`. The checks need
`db`, `redis`, `web`. The rest is resident memory, and memory pressure is what turns a
busy box into an unresponsive one. The instance is a `t3.xlarge` with a **20 GiB** root
volume (`variables.tf`) — small enough that Docker builds plus eight containers put the
box into I/O wait, which is the more likely reading of `load average: 84` with no CPU
work on an AL2023 image that has no swap configured. The same repo's CI already runs the
gate lean (dedicated compose file + `--no-deps`).

---

## 3. Decisions

### Platform — `AixleHQ/flow`

**D-0 — Degradation contract (binds every decision below).**
A workspace is rejected only on **positive evidence that it is sick**. Absence of a
signal is never evidence: a box from a template that predates this work — no agent health
in the API response, no `/var/lib/aixle-jobs`, an agent running as `ec2-user` instead of
root, a Coder version that reports a different shape — must allocate exactly as it does
today. Concretely:

- Missing / unparseable agent health → candidate kept.
- Probe error attributable to *our* side (the `coder` CLI missing from the Rails image
  → exit 127, auth failure, integration misconfiguration) → candidate kept, nothing
  quarantined. A platform-side fault must not empty every pool at once.
- Probe output that does not parse (no `/proc/loadavg`, `nproc` absent, BusyBox) → the
  load check is skipped, the reachability result still counts.
- If every candidate is rejected by the *active* probe, allocation does not fail: it
  falls back to the least-bad candidate (lowest observed load, then most recently
  healthy) and returns a `health_warning` field alongside the normal payload. Raising
  `ExhaustedError` when boxes exist would be a regression against today's behaviour.
- The active probe is killable: `Settings.coder.health_probe_enabled` (default true),
  overridable per integration. Passive filtering stays on — it costs nothing.

**D-1 — Health-gated allocation (two tiers).**
*Passive:* when the list response carries agent data, drop candidates whose every agent
says `status != "connected"` or `health.healthy == false`. Explicitly unhealthy only —
`nil`, `[]` or an unknown shape leaves the candidate in. Costs zero extra API calls and
removes the amber box.
*Active:* after the lock is taken, probe over SSH with a short deadline
(`uptime; cat /proc/loadavg; nproc`, 15 s). Reject on timeout (unresponsive box), on a
non-zero exit that came from the remote shell, or when 1-minute load exceeds
`2 × vCPU`. Distinguish that from a local `coder ssh` failure (exit 127, auth), which is
not the workspace's fault and is handled per D-0. On rejection release the lock and
continue to the next candidate. `status: "running"` is never evidence again.

**D-2 — Quarantine, with a cooldown.**
A rejected workspace gets an `IntegrationData` row `coder:workspace_health:<name>` with
`expires_at = now + Settings.coder.unhealthy_cooldown_minutes` (default 30) and a value
recording the probe output and reason. The allocator skips workspaces with a live
quarantine row; a successful probe deletes any stale row. Reuses the existing table,
the `live` scope and the `(integration_id, key)` isolation the lock service already
relies on — no migration.

Per D-0, a row is written only for evidence about *that workspace* (unresponsive,
overloaded, remote command failed). Platform-side faults never write one. The cooldown is
bounded and self-healing: worst case a healthy box is unavailable for 30 minutes, and the
D-0 fallback still hands it out if nothing better exists.

**D-3 — `exclude` on `coder_allocate_machine`.**
`exclude: ["collectively-prod-920a776c"]` — array of names the caller will not accept.
This is the escape hatch a session needs at exactly the moment it has evidence the
server does not (a box that answers the probe but fails the actual work). Excluded names
are skipped before locking, and the response reports which ones were skipped.

**D-4 — Locks age from last activity.**
Add `LockService#touch(workspace_name:, terminal_session_id:)` that pushes `expires_at`
forward by the TTL, and call it from `coder_ssh_exec` on every successful ownership
check. Lower the default TTL from 60 to 30 minutes. Net effect: an abandoned lock frees
the box in ~30 minutes of true silence instead of 60 minutes of wall clock, while an
active 90-minute session never loses its box. Renewal is a single indexed `UPDATE` on a
row the tool already loaded.

**D-5 — Detached execution as a tool affordance.**
`coder_ssh_exec` gains `detach: true`. The runner then executes

```sh
mkdir -p /var/lib/aixle-jobs
nohup setsid sh -c '<command>' > /var/lib/aixle-jobs/<job_id>.log 2>&1 &
echo $! > /var/lib/aixle-jobs/<job_id>.pid
```

wrapped so the exit status lands in `<job_id>.exit`, and returns `{job_id, log_path}` in
under a second — no timeout exposure. A new `coder_job_status` tool returns
`{state: running|exited, exit_code, tail}` reading pid/exit/log. The rule the sessions
derived four times independently ("never re-issue the gate; poll it") stops being
something an agent must remember and becomes the only shape the tool offers for long
work.

Per D-0 the wrapper provisions its own preconditions rather than assuming a template
provides them: it creates the job directory itself, falls back to `$TMPDIR`/`/tmp` when
`/var/lib/aixle-jobs` is not writable (agent not running as root), and degrades to plain
`nohup … &` when `setsid` is absent. `coder_job_status` on an unknown or vanished job id
returns `state: "unknown"`, never an error that reads as "the job failed".

**D-6 — Truthful timeouts.**
Measure the actual ceiling end-to-end (MCP client → ingress → Rails), clamp
`SshRunner::MAX_TIMEOUT` to it, and state it in the tool description instead of the
current "max 600". On timeout the payload gains an explicit advisory:

> The remote command may still be running — the SSH channel was killed, not the work.
> Do NOT re-issue it. Re-run with `detach: true` and poll `coder_job_status`.

**D-7 — Actionable exhaustion, no silent template fallback.**
When every candidate is locked, quarantined or excluded and the integration has no
`default_template`, `ExhaustedError` must name the pool size, how many were rejected for
which reason, and the exact setting to configure. A silent fallback to
`Settings.coder.default_template` is rejected: on a self-hosted install it would create
billable cloud resources the operator never asked for.

**D-8 — `coder_list_machines` (diagnostics).**
Read-only view of the pool: name, build status, agent health, lock holder + expiry,
quarantine state. Turns "allocation is starving" from a 40-minute investigation into one
call. Phase 3.

**D-9 — Server-side `HOME`.**
`SshRunner` prefixes every command with a fallback chain rather than a hardcoded
`/root`, since an agent running as `ec2-user` cannot write there:

```sh
export HOME="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"; export HOME="${HOME:-/tmp}";
```

Removes RC-5.1 for all integrations immediately, without waiting for an image or template
release, and stays correct after the template fix lands (where `HOME` is already set, the
prefix is a no-op).

**D-10 — Platform owns repo bootstrap, not the image.**
The credentials for cloning a private product repo (GitHub App installation token) live
in the platform, not in the AMI. A `coder_prepare_repo` step — full clone (no
`--filter`), all branches, tokenised `remote.origin.url` rewritten on each allocation
because the token is short-lived, `GIT_TERMINAL_PROMPT=0` — belongs on the platform side
and fixes RC-5.2–5.3 for every project rather than one template.

### Infrastructure — `aixle-infra`

**D-11 — Reconcile the live template with Terraform first.**
`coder templates pull aws-ec2-spot-v1` and diff against
`terraform/coder/templates/staging/aws-ec2-spot-v1`. Everything below assumes the repo is
the source of truth; if it is not, that is the first fix.

**D-12 — `aws-ec2-spot-v2`, published alongside v1.**
A new template version rather than an edit of `aws-ec2-spot-v1`, and deliberately
*not* pinned to one project: the fixes below (`HOME`, buildx, disk, log rotation) are
generic, and per-project pinning would mean maintaining the same corrections N times.
Publishing as v2 also keeps the blast radius small — the root-volume change forces
instance replacement, so existing workspaces are migrated by creating new ones, not by
mutating the template they already run.

Once v2 exists, the integration's `default_template` can finally be set, so allocation
creates a workspace on demand instead of dividing a fixed set — a better fix for RC-2
than any exclusion logic. Existing `collectively-prod-*` and `aixle-prod-*` boxes stay on
v1 until recycled; workspace naming (which is what `machine_prefix` filters on) is chosen
by the platform at creation and is independent of the template.

**D-13 — What v2 corrects:**
- `coder_agent.main.env` gains `HOME`, `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/bin/true`
  (RC-5.1–5.2 at the source).
- `buildx` pinned and installed by the agent's startup script rather than inherited at
  0.12.1 from the AL2023 `docker` package (RC-5.5). Doing it in the startup script and
  not in the Packer bootstrap means no AMI rebuild is on the critical path — the
  bootstrap should still gain it later so a fresh image starts correct.
- Root volume 20 → 64 GiB (RC-6). This forces instance replacement, which is why v2 is a
  new template rather than an edit of v1.
- `git config --system --add safe.directory '*'` (RC-5.4).
- Docker json-file log rotation and a build-cache prune above 80% disk — the two ways
  this box fills its root volume, which is the likelier reading of `load average: 84`
  with no CPU work than swap (RC-6).
- `/var/lib/aixle-jobs` created at start, as the landing zone for D-5's detached runs.
  The runner still provisions it itself (D-0) so v1 boxes keep working.
- Still does not start the product stack (RC-6).
- Still does not clone the repo: the credential for a private clone lives in the platform
  (D-10), and the workspace instance profile carries SSM permissions only.

**D-14 — Recycle the two damaged boxes.** `collectively-prod-920a776c` and
`collectively-prod-aa9f2995`. Operational, immediate, independent of every code change
above.

---

## 4. Phasing

| Phase | Contents | Repo | Unblocks |
|---|---|---|---|
| 1 | D-1, D-2, D-3, D-4, D-9 | flow | A sick box is never handed out, and a session that finds one can leave. Stale locks stop shrinking the pool. |
| 2 | D-5, D-6 | flow | A 15–25 min gate can run at all. Double-gate self-DoS becomes impossible. |
| 3 | D-7, D-8, D-10 | flow | Starvation and per-session git tuition become diagnosable / gone. |
| 4 | D-11, D-12, D-13 | aixle-infra | On-demand workspace creation; lean boxes; no rediscovered workarounds. |
| — | D-14 | ops | Immediate. |

Phases 1 and 2 are independent of phase 4: they fix all four reported faults at the
platform layer even if no template ever changes.

## 5. Verification

Mirrors the field report's own "what fixed would look like":

1. Three consecutive allocations in one session, with a release between each, return
   different workspace ids — or a freshly created one. *(Test: allocator returns the next
   candidate when the first is quarantined / excluded.)*
2. A saturated or agent-unhealthy workspace is never handed out. *(Test: passive filter
   drops an agent with `health.healthy == false`; active probe rejects a box whose
   loadavg exceeds the threshold and writes a quarantine row.)*
3. A fresh workspace runs `git fetch --unshallow` and the full gate with no per-session
   workarounds, and completes. *(Manual, phase 3–4.)*
4. `docker ps` on a fresh workspace shows the lean set. *(Manual, phase 4.)*
5. A gate started with `detach: true` survives past the transport ceiling and its exit
   code is retrievable via `coder_job_status`. *(Test: detached invocation returns a
   `job_id` without blocking; status transitions running → exited.)*
6. **Degradation (D-0).** A workspace whose API response carries no agent health data is
   still allocated. A probe that fails for a platform-side reason (`coder` CLI missing →
   exit 127) allocates as before, quarantines nothing, and says so. A pool where every
   probe rejects still returns the least-bad workspace with `health_warning` set rather
   than `ExhaustedError`. A detached run works on a box that has no
   `/var/lib/aixle-jobs` and no `setsid`. *(Tests: one per clause — this is the
   regression surface, since every box in the field today predates v2.)*

Backend tests live in `test/services/coder/` and
`test/services/internal_tools/coder_tools_test.rb`; follow `docs/testing.md` — the Coder
API is stubbed at `Coder::Api`, SSH at `Coder::SshRunner`, never with `any_instance`.

## 6. Out of scope

- **Prebuilding the workspace image** (pulling a warm image from a registry instead of
  building on the box). Overlaps RC-5/RC-6 and is tracked on the product side. It reduces
  the pain but does not fix RC-1–RC-4 — a prebuilt image handed out by a broken allocator
  is still a broken allocator.
- **Widening `TEST_LOCK` in the product repo** to cover `rubocop`/`brakeman`/`eslint`/
  `tsc`/`vitest`. Worth doing, but it belongs to the product repo and only mitigates a
  symptom of RC-4; D-5 removes the cause.
- Spot-interruption handling and the workspace autostop policy.
