# Expired agent logins during running sessions: refresh like a laptop, pause instead of dying

**Status:** research spike (board task #2731), no implementation
**Date:** 2026-10-08
**Scope:** Claude Code first, because its rotating 8-hour OAuth grant causes almost every failure.
The pause/resume half applies to every runtime.
**Related:** `docs/design/agent-credential-lifecycle.md` (what has shipped so far),
`docs/research/technical-container-token-brokering-research-2026-09-05.md` (broker options, ToS constraint)

---

## Summary

- **Most mid-run deaths are collisions, not expiries.** Take two or more containers of one user
  that are busy when the 8-hour boundary passes. The sweep stands down because a holder is
  mid-turn, so each CLI refreshes on its own about 5 minutes before expiry. The first container
  to refresh rotates the single-use refresh token. The others then get a 401 and try to refresh
  with the token that was just rotated out. They get `invalid_grant`, wipe their own credential
  file and print `Login expired · Please run /login`. The winner's new token reaches our database
  about 20 seconds later, and nothing sends it on to the losers.
- **A laptop does not have this problem, and the reason can be read from the CLI.** Claude Code
  2.1.281 serializes refreshes with a lockfile next to the one shared credentials file. It
  re-reads that file inside the lock and again on every 401. Our containers keep the re-read,
  because it lives in the CLI. They lose the shared file and the lock.
- **When a login really dies, nothing pauses.** Detection comes at least 30 minutes late and only
  for non-interactive steps. The step is marked failed, the run fails and cancels its sibling
  steps, and the pod is deleted along with the agent's conversation. There is no resume.
- **Recommendation: make the platform the lock (Approach B), and pause in place.**
  - Route container refreshes through our server via the proxy that already runs in every
    container. The first refresh is real. Later ones that present the rotated-out token get the
    current tokens back, which is exactly what the CLI does inside its lockfile on a laptop.
    Every new token is sent to every container holding the grant.
  - When a login is genuinely dead, keep the container alive and mark it as waiting for auth.
    Tell the user. When they re-authenticate anywhere, hand the new grant to every waiting
    container and nudge each agent to continue.
- **Rough effort:** 2–3 days of probes and quick wins, about 1 week for prevention, 1.5–2 weeks
  for pause/resume. Resuming in a new container (`--resume`) was considered and declined: it
  brings back the conversation but not the filesystem (§5, Phase 3).

---

## 1. Why a laptop survives and a container does not

Read from the Claude Code 2.1.281 binary pinned in `aixle/claude-code` (`/etc/aixle-cli-version`).
The bundle is minified, so event names are quoted as they appear in it.

| Laptop behaviour | How CLI 2.1.281 does it | What happens in our containers |
|---|---|---|
| Every process reads one credential store | `~/.claude/.credentials.json` | One copy per container, plus our database row |
| Refreshes are serialized across processes | Lockfile `~/.claude/.oauth_refresh.lock` (proper-lockfile, 60 s stale, 5 retries). On contention it says "another Claude Code process is refreshing it" | The lock lives on each container's own filesystem, so there are N independent locks |
| Inside the lock, the store is re-read. If someone else already refreshed, their token is used | `tengu_oauth_token_refresh_race_resolved` | Works only if somebody wrote the new token into *this* container's file |
| On a 401, the cache is cleared and the store re-read. A different token is adopted before trying its own refresh | `tengu_oauth_401_recovered_from_keychain` | Same. This is what makes delivering a token into a busy container safe |
| On `invalid_grant`, the refresh token is marked dead and the tokens on disk are blanked, but only if the file still holds that token (compare-and-clear) | `tengu_oauth_refresh_token_cleared_on_disk` | The loser wipes its own copy. Our database is safe: a blanked block has `expiresAt: 0` and never wins `ClaudeCodeAdapter#freshest_oauth_block` |
| A process whose login died stays alive with its conversation. `/login` in any terminal fixes the others on their next request. Daemon mode even polls the store every 30 s and resumes on its own | `auth: no token found, will re-check keychain every 30s` | The session is reaped after 30 minutes and the pod deleted |
| Refreshes proactively 5 minutes before expiry | `now + 300000 >= expiresAt` | The sweep refreshes 15 minutes ahead, but defers while any holder is busy |

Anthropic's own hosted sessions solve the same problem from the other side. When
`CLAUDE_CODE_REMOTE_SESSION_ID` is set the CLI is in "runner rotation" mode:

- The container has no refresh token.
- On a 401 it waits up to `CLAUDE_CODE_OAUTH_401_WAIT_MS` (60 s) for the runner to drop a new
  token into `/home/claude/.claude/remote/.oauth_token`.
- After `CLAUDE_CODE_AUTH_FAIL_EXIT_MS` (10 minutes) it exits, quoting the bundle, "so the runner
  recycles this session with fresh credentials".

That supports the direction proposed here: one party rotates, containers read through it, and a
container that cannot recover waits and is then recycled. Those switches belong to Anthropic's
hosted runtime, so we cannot build on them (Approach C).

**So, to "can it work the way it does on a local machine": yes.** The CLI already does its half.
We have to supply the two things a laptop gets for free:

- one store that every holder reads (the database row, plus fan-out to every holder);
- one lock that every refresh happens under (the platform).

---

## 2. Root cause

### 2.1 Where an expiry surfaces today

The path for a Claude workflow step:

1. The CLI fails its 401 recovery and prints `Login expired · Please run /login` (or
   `OAuth token revoked`). The TUI process stays alive, waiting for input, with the
   conversation in memory.
2. Nothing notices in real time.
   - `AuthErrorDetector` (`app/services/auth_error_detector.rb`) has only two callers: the
     no-output watchdog, which uses it to word its message, and `CompleteStepActivity`, which
     looks after the session has already ended.
   - The per-minute pane scan (`ScanQuotaErrorsActivity`) looks for quota and prompt patterns
     only.
3. `ScanNoOutputSessionsActivity` fails the session after 30 minutes of silence. It only does
   this for `ready` workflow steps that are not interactive. Interactive steps and
   `agent_session` sessions wait for the 25-hour stale reaper or the 23-hour exec timeout.
4. `SessionService.fail_session` starts cleanup. Logs are collected, rotated credentials are
   merged back, and the pod is deleted. Pods have no volumes
   (`ContainerRuntime::KubernetesRuntime`) and nothing passes `--resume`, so the conversation is
   gone.
5. `CompleteStepActivity` marks the step failed with `error_category: :auth_expired`
   (`complete_step_activity.rb:136`). It does not touch the credential and sends no mail.
6. **The run.**
   - With `on_failure: retry`, a new container starts from scratch. Its preflight may then
     refuse the launch: `AgentCredential#unrecoverably_expired?` (`agent_credential.rb:379`)
     treats an expired credential that another session holds as dead. The launch relay then
     cancels the session, and V2 cancels the whole run.
   - Without retry the run fails, and `WorkflowService#fail` → `fail_active_step_runs`
     (`workflow_service.rb:156`, `:307`) takes the sibling steps down with it.

### 2.2 Why an auth error ends up fatal

No single decision makes it fatal. There is simply no state to put the session in instead:

- `TerminalSession` has no paused state.
- `StepRun#mark_waiting!` (`step_run.rb:44`) exists but has no callers.
- `WorkflowRun`'s `paused` state is never entered.

So every path ends in `failed` or `cancelled`.

### 2.3 Why the grant dies, and why holders die together

All containers of one user share one `AgentCredential` row per (user, company, agent). There are
four ways that row's holders die together:

- **(a) A collision between busy holders. This is the main hypothesis.**
  - `refresh_held` (`refresh_expiring_tokens_activity.rb:50`) skips a rotating credential while
    any holder is mid-turn. The comment there explains why: rotating under a working agent is
    what the 2026-09-05 incident looked like.
  - A multi-agent run keeps several holders busy all the time, so the sweep never acts and every
    CLI refreshes at T−5 minutes. The losers die within seconds of the winner.
  - The watcher's write-back (`docker/base/watcher/index.js` → `AgentCredentialSyncController`)
    stores the winner's token, but `Agents::CredentialDelivery` is only ever called by the
    sweep, so no other holder receives it.
- **(b) A run-level cascade.** One step failing on auth fails the run, and the run cancels its
  other running steps. A worker can be killed while its own credential is perfectly good.
- **(c) A genuinely dead grant:**
  - the refresh token expired (seen on credential 49, `Refresh token expired`, 2026-09-24);
  - the grant was revoked, or the account was put on hold;
  - Kiro IdC logins hit an 8-hour directory cap.

  Every holder dies at its next refresh, and the only recovery is a new run after a re-login.
- **(d) A launch bug, now fixed.** Until #400 (2026-10-01), a refresh at launch handed the
  container the pre-rotation copy. The incident in the task may predate that deploy.

**The code cannot tell which of these took down the orchestrator and the worker in the reported
incident.** Query Q1 in §6 settles it. The likely shape is one of these, both of which share the
user's one credential row:

- an Aixle Builder session, which is interactive and starts runs through the builder toolset;
- a parallel DAG step;

either one together with a worker step.

---

## 3. The task's questions, answered

| Question | Answer |
|---|---|
| Where and how does expiry surface? | §2.1. As a TUI banner nobody reads for 30 minutes, and only for non-interactive steps. |
| Why is an auth error fatal rather than retryable or paused? | §2.2. There is no paused state for a session, step or run, and a failed step cancels its siblings. |
| Can we refresh proactively? | We already do: the sweep refreshes 15 minutes ahead and a launch refreshes 60 minutes ahead. The gap is busy holders. Refreshing under a busy CLI is safe for 2.1.281, because it re-reads the file on a 401 and inside its lock. One gap remains: the seconds between our rotation and the new file landing (probe P1). Approach B closes it. |
| Can the orchestrator hold workers paused and resume them once any session re-authenticates? | Yes. Every holder shares one row, so "any session re-authenticated" means "the row now has a newer grant". Fan that grant out to every holder and nudge the paused ones. **Prerequisite:** an identity check on write-back. `ClaudeCodeAdapter` has no `credential_identity` (Codex, Cursor and Kiro do), so a `/login` to a different account inside a container would be accepted and fanned out today. |
| What state must be persisted to resume? | **Resuming in place:** nothing new. The live container *is* the state: CLI process, conversation and workspace. **Resuming in a new container:** the conversation and the filesystem have to come back *together* — see §5, Phase 3. `--resume` restores only the conversation. That is why in-place comes first. |
| How should the user be notified, and where do they re-authenticate? | Notify on the run page and the board task (`auth_expired` is not rendered anywhere today), by email (`AgentCredentialMailer` currently fires only on server-side refresh failures), and in the Slack/Teams thread a run came from. Re-authentication happens on Profile through the existing `?authenticate=claude_code` deep link and `auth_setup` flow. Once the identity check exists, `/login` typed into the paused session's own terminal can work too, which is the laptop way. |
| Do flow and palad-app differ? | Not in code: palad-app is a deployment of flow. They differ in deployment: (1) prod and staging run EKS pods with no shared volumes, which rules out the cheap form of Approach A; (2) prod images lag develop, so check the deployed SHA includes #279, #285, #400 and #405 before reading prod data; (3) OSS self-hosters run Docker, where a shared volume would be trivial. |

---

## 4. Candidate approaches

The work has two halves:

- **Prevent:** keep the grant alive while N containers hold it.
- **Recover:** pause, notify and resume when the grant really dies.

Recovery is needed whichever approach is chosen, so it is described once (R). The approaches
differ on prevention.

### R — pause in place (common to every approach)

- **R1 Detect within a minute.**
  - Run `AuthErrorDetector` in the per-minute pane scan for every session kind, not only
    non-interactive steps.
  - Treat a permanent server-side refresh failure as a signal for every holder of that row.
- **R2 Pause.**
  - Add an `awaiting_auth_since` mark on the session. It is not a new state-machine state: the
    session is still `ready` and its container is up.
  - The no-output watchdog and the stale reaper skip a marked session.
  - Its step moves to `waiting_input`, which exists but is unused, with a reason. The run shows
    `paused`, which also exists but is unused.
  - Sibling steps are not cancelled, and the V2 loop keeps polling.
  - A pause is bounded by the 23-hour exec deadline and by a configurable cap. When the cap
    runs out, the session fails exactly as it does today.
- **R3 Notify.** Once per credential per pause episode, on every channel listed in §3.
- **R4 Resume.**
  - Trigger: any newer grant on the row, whether from a Profile re-auth, any holder's
    write-back, or a sweep refresh.
  - `CredentialDelivery` writes the grant to every holder.
  - Each waiting session gets a nudge typed into tmux: "Authentication was restored. Continue
    from where you stopped." The mark is then cleared.
  - The nudge belongs to the adapter. A TUI CLI gets a prompt; a CLI that has exited needs a
    relaunch with its resume flag.
- **Costs.**
  - A paused session keeps its admission slot and its container.
  - Whether paused minutes are metered for billing is a product decision.

### Approach A — a shared credential volume (the literal laptop)

**How it works.**

- Mount one directory per (user, company, agent) into every container on that grant: a named
  volume on Docker, EFS (ReadWriteMany) with one access point per grant on EKS.
- Point the CLI's credentials file at that directory.
- The CLI's own lockfile and re-read then do all the work.
- The server refreshes by taking the same lockfile from a pod that mounts the volume.

**For:** exactly the local semantics, with no vendor protocol code, for every kind of refresh.

**Against:**

- **Infrastructure.** EFS CSI driver, a ReadWriteMany storage class and per-tenant access
  points in aixle-infra.
- **Runtimes.** Coder and remote runtimes cannot mount the volume.
- **Locking.** A lock over NFS depends on `mkdir` being atomic and on mtime staleness, which is
  sensitive to clock skew.
- **Secrets.** They leave the encrypted database column and sit on a filesystem.
- **Protocol coupling.** The server has to speak the CLI's internal lockfile protocol, which
  can change in any release.
- **Kiro.** Its SQLite store is unsafe over NFS, so in practice this is Claude-only.
- **Merge guards.** They are lost: a CLI that writes junk propagates it instantly.

**Effort:** about 2 weeks including infrastructure. High operational risk.

### Approach B — the platform is the lock (recommended)

- **B1 Fan-out.** Every accepted newer grant (watcher write-back, sweep, launch top-up,
  re-auth) is delivered to every other live holder. Cheap, and it closes "the loser never hears
  about the winner".
- **B2 Refresh coalescing.** The in-container proxy intercepts refresh requests to the vendor's
  token endpoint. For Claude that is `POST platform.claude.com/v1/oauth/token` with
  `grant_type=refresh_token`, or `api.anthropic.com/v1/oauth/token` for Platform logins. It
  forwards them to a new `POST /agents/credentials/refresh`, authenticated by the same
  per-session key as the write-back. Under `credential.with_lock`, the server handles four cases:

  | Refresh token presented | Server does |
  |---|---|
  | The stored one | A real refresh: persist, fan out, return the vendor's response verbatim |
  | One rotated out of that block recently (digests kept about 24 hours, the longest a session lives) | Returns the current stored block as a token response. This is what the CLI does inside its lock (`race_resolved`) |
  | Unknown (a fresh `/login` inside that container) | Passes it through to the vendor, then checks identity and persists |
  | Our endpoint is unreachable | Passes it through (today's behaviour) |

- **B3 The sweep may then refresh busy holders**, so `skipped_busy` goes away. A holder that
  gets a 401 before delivery lands refreshes through us and receives the current token instead
  of `invalid_grant`.
- The launch refusal for "held and expired" (`unrecoverably_expired?`) can go for refreshable
  credentials.

**For:**

- Removes the race for every trigger: proactive refresh, a 401 and launch.
- Needs no shared storage, and works on Docker, EKS and Coder.
- The pattern carries to the other rotating runtimes (Codex, Grok, Kiro, Antigravity) through
  an adapter hook.
- Keeps database encryption and the merge guards.
- Fails open: if anything is down, behaviour is today's.

**Against:**

- **It depends on the proxy seeing the refresh.** It does today for Claude: `http.log` shows the
  CLI's refresh calls to `platform.claude.com`. Auth bodies are currently streamed, not
  buffered, so this one path needs buffering. A CLI that stops honouring `HTTPS_PROXY` falls
  back to today's behaviour.
- **The synthesized response has to match the vendor's shape.** Pin it with a contract test per
  adapter.
- **ToS posture is unchanged.** We already refresh server-side (see the brokering research);
  this adds no new route for inference traffic.

**Effort:** B1 2–3 days; B2 and B3 about 1 week (proxy addon, endpoint, rotated-digest storage,
adapter hook, tests, image rebuild).

### Approach C — the container never holds the grant

**How it works.** Containers get only an access token. The platform rotates the grant and
pushes the new token in. This is Anthropic's own "runner rotation".

**The documented knobs do not work:**

- `ANTHROPIC_AUTH_TOKEN` is an environment variable, so it does not reload. That puts a hard
  8-hour ceiling on every session.
- A credentials file with no refresh token does not work either. The CLI's no-refresh-token 401
  path waits for a new token only when `CLAUDE_CODE_OAUTH_TOKEN` or the hosted runtime's token
  file is in use. Otherwise it prints `Login expired` rather than re-reading the file.

**The undocumented switches are worse.** Making C work means using the hosted runtime's internal
switches (`CLAUDE_CODE_REMOTE*`, `/home/claude/.claude/remote/.oauth_token`):

- that impersonates Anthropic's hosted runtime;
- the switches are undocumented and can break in any release;
- it is hostile to the ToS.

`apiKeyHelper` is still blocked on the header probe from the brokering research.

**The durable form of C is the API-key path**, which the ToS research already prescribes for
unattended runs: an API key has no refresh token, so there is nothing to race and nothing to
expire mid-run.

**Effort:** cannot be built on subscription OAuth today. The API-key path is a product decision.

### Comparison

| | A shared volume | B platform lock | C no grant in container |
|---|---|---|---|
| Removes the rotation race | yes | yes | yes |
| Works on EKS without new infra | no (EFS) | yes | — |
| Works for Codex/Grok/Kiro too | no (Kiro unsafe) | yes, per-adapter hook | no |
| Depends on CLI internals | lockfile protocol | refresh endpoint shape (public OAuth) | hosted-runtime switches |
| Failure mode | shared junk, NFS lock | falls back to today | session dies at 8 h |
| Effort | ~2 wks + infra | ~1.5 wks | n/a (API key: product) |

---

## 5. Recommendation and breakdown

**Build B and R, in shippable phases.** Phase 1 removes most of the deaths. Phase 2 makes the
remainder recoverable.

**Phase 0 — measure (2–3 days).**
- T0.1: run probes P1–P4 (§6) on staging.
- T0.2: run Q1 against production to split the last 30 days of auth deaths into (a)–(d).

**Phase 1 — stop the collisions.**
- T1.1: fan-out after every accepted write-back, refresh and re-auth (B1).
- T1.2: identity check on Claude write-back (`oauthAccount.accountUuid` and
  `organizationUuid`), as Codex, Cursor and Kiro already have.
- T1.3: the refresh-coalescing endpoint, plus storage for rotated refresh-token digests (B2,
  server side).
- T1.4: the proxy addon for the refresh path, with buffering (B2, container side), and an image
  rebuild.
- T1.5: let the sweep refresh busy holders, and drop the "held and expired" launch refusal for
  refreshable credentials (B3). Do this only after T1.3–T1.4 are live.
- T1.6: a refresh event log and sweep counters (the open Layer 4 item in the lifecycle
  design), so collisions can be watched going to zero.

**Phase 2 — pause instead of die.**
- T2.1: auth detection within a minute, for every session kind (R1).
- T2.2: `awaiting_auth` on the session, step and run. Exempt marked sessions from the watchdog,
  the stale reaper and sibling cancellation. Enforce the cap (R2).
- T2.3: resume through delivery plus a nudge, per adapter (R4).
- T2.4: notifications: run and board banner, email, chat thread, re-auth deep link (R3).
- T2.5: show the paused state in the run page, the board, and Slack/Teams status cards.

**Phase 3 — resume in a new container: declined (2026-10-08).** Kept here for the reasoning. A
pause that outlives its container fails the step, exactly as today. Revisit only if Phase 2 data
shows pauses regularly outliving their containers (the 23-hour exec deadline, an eviction, a lost
node).

**`claude --resume` restores the conversation, not the filesystem.**

- It replays the transcript `~/.claude/projects/<cwd>/<id>.jsonl`: messages, tool calls and
  their results.
- The transcript's `file-history-snapshot` entries point at `/rewind` backups in
  `~/.claude/file-history/`. Those are backups taken before Edit/Write calls, for going
  *backwards*. They cover nothing a shell command changed, so they cannot rebuild a workspace.
- A new pod clones the repositories fresh (`SessionContextService`), so every uncommitted change
  is gone.

Resuming the conversation on that clean checkout is worse than today's from-scratch retry. The
agent believes its edits are on disk, so Edit calls miss, its summaries describe files that do
not exist, and it can report work as done that was never kept. **The conversation and the
filesystem come back together, or neither does.**

Two ways to keep them together:

- **Snapshot at pause, restore before resume.** In the auth case the container is still alive
  when the pause starts (R2), so it can be captured:
  - `/workspace`, or a `git stash`-style commit of every repository including untracked files,
    pushed to a platform-owned ref;
  - the agent's `~/.claude`: transcript and file history, kept encrypted, not redacted.

  The new pod restores both before it runs `claude --resume <id>`.
- **A per-session volume** (a PVC on EKS, a named volume on Docker) for `/workspace` and the
  agent home, so a replacement pod mounts the same disk. This also covers pods that die for
  reasons other than auth. It costs volume provisioning, availability-zone pinning and attach
  time.

What neither brings back, so the resume nudge has to say so:

- running processes (dev servers, watchers, background jobs);
- anything installed outside the snapshot (system packages, global npm, files in `/tmp`);
- environment changes made in the old shell.

**Fallback when no snapshot exists:** no `--resume`. Start a fresh session and hand it the
facts: the step note, outputs and pushed branches from the dead session, plus a summary of its
transcript. The agent then re-reads the real files rather than trusting its memory of them.

**Acceptance scenario on staging:**

1. Two busy parallel steps cross the expiry boundary → zero failures.
2. Revoke the grant mid-run → both steps pause within a minute and one email is sent.
3. Re-authenticate on Profile → both steps continue and the run completes.

---

## 6. Probes and queries to run first

- **P1. Does a refresh revoke the previous access token immediately?** This sets the size of
  the gap between our rotation and delivery landing. It decides whether B1 on its own is
  enough to let the sweep refresh busy holders.
- **P2. Live delivery.** Write a new `.credentials.json` into a container whose agent is
  mid-turn. Confirm the CLI adopts it without failing a turn. The CLI source says it will. The
  comment in `Agents::CredentialDelivery` still calls this unverified.
- **P3. Reuse.** Refresh twice with the same refresh token a few seconds apart. Does the second
  call get `invalid_grant`? Does it revoke the whole family, so the token the first call minted
  dies too? If the family is revoked, a collision kills the winner as well, which would explain
  "both died".
- **P4. Refresh-token lifetime.** How long until `Refresh token expired` for a grant that is
  refreshed regularly, compared with one left idle? This sets how often Phase 2 will fire in
  practice.
- **Q1 (production).** For each step run failed with `auth_expired` in the last 30 days:
  - how many other live holders the credential had at the moment of failure;
  - the time between the last write-back from any holder and the failure;
  - whether the row stayed `active` (collision) or went `error` (dead grant);
  - whether sibling steps were cancelled by the run (cascade).

---

## Appendix — where `docs/design/agent-credential-lifecycle.md` has drifted from the code

Found while mapping the code for this spike. To be fixed in that document when Phase 1 lands.

- The M2 row and blind spot B2 say the sweep skips held credentials. It now refreshes them and
  delivers when every holder is parked.
- §2a says write-back uses `merge_refreshed_credentials`. It uses the stricter
  `merge_container_credentials`.
- The watcher lives at `docker/base/watcher`, not `docker/shared/watcher`.
- §2b says delivery uses `write_to_container`. It writes only `credential_files` through
  `deliver_credential`.
- §3.1 says the watchdog cancels sessions. It now fails them through `fail_session`.
- B5 says there is no `error` status and no mailer. Both exist now.
- Several line references are stale. `REFRESHABLE_AGENT_TYPES` is derived now, not a literal.
- `finishing` sessions are neither holders nor allowed to write back, so the sweep can rotate
  under a session that is mid-cleanup. The document does not cover this case.
