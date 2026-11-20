# Suspending and restoring interactive sessions

Status: built 2026-11-20 (PR #802). Decisions taken the same day; §12 lists where the build differs from the proposal. The facts it builds on are in [research/technical-session-restore-and-sharing-research-2026-11-19.md](../research/technical-session-restore-and-sharing-research-2026-11-19.md), including the live probe of conversation resume for all eight agent CLIs.

## 1. What and why

Today an interactive session that reaches the 23-hour limit is finished: the container is deleted with everything in it, apart from `/workspace/outputs`, which becomes assets. Work the agent did not push is lost, and so is the conversation. A user shaping a PRD over several days loses it overnight.

Instead, an interactive session is **suspended**:
- **What is saved:** its conversation, its files and its unpushed git work go into one archive in object storage, and the container is deleted.
- **What it costs while suspended:** it holds no container, no admission slot and no billing.
- **Restore:** within 30 days the owner can **Restore** it. A new session starts with the same configuration, the files are put back, and the agent CLI resumes the same conversation.

## 2. Decisions

| # | Decision |
|---|---|
| 1 | Only interactive `agent_session` sessions can be suspended, Aixle Builder included. Workflow steps, `auth_setup` and `tool_setup` never are |
| 2 | Two triggers: reaching the 23-hour limit, and a **Suspend** button. **Finish** still finishes. A session whose container died is still failed: there is nothing left to save |
| 3 | Restore creates a **new** session (`restored_from_session_id`). The suspended one becomes `restored` once the new one is running |
| 4 | Outputs are not turned into assets at suspend. The archive holds the whole `/workspace` apart from `repo/`, `assets/`, secret files and rebuildable directories (§4.1) |
| 5 | Repositories: the branch and commit are recorded. Unpushed commits go into a `git bundle`, uncommitted changes into a patch, untracked files into a tarball, all inside the archive. Nothing is pushed to the customer's remote |
| 6 | Assets are restored from the session's own `input_assets`, at their current version |
| 7 | The CLI resumes its conversation by id. If it cannot, it starts fresh with the old conversation left as a file |
| 8 | The suspend phase gets its own long timeout. An archive lives 30 days and its owner is told so. After that a sweep deletes it and the session becomes `finished` |
| 9 | Suspend works wherever the archive can go straight to S3-compatible storage. Without it, a session finishes as today |

## 3. Lifecycle

### 3.1 States

```
ready ──Suspend──▶ finishing (+ suspend_requested_at) ──┐
ready ──23-hour limit───────────────────────────────────┤
                                                         ▼
                                   cleanup takes the checkpoint
                                     │                    │
                                 stored                 failed
                                     ▼                    ▼
                                suspended              finished
                                 │      │
                     Restore, new │      │ 30 days
                  session ready   ▼      ▼
                             restored   finished (suspend_expired)
```

- **While the checkpoint is taken** the session is `finishing` with `metadata.suspend_requested_at` (Suspend), or still `ready` (the limit). There is no separate `suspending` state: every list, scope and scanner already knows what `finishing` and `ready` mean. The page shows "Saving files and conversation…" for a finishing session with the flag (`TerminalSessionResource#suspending`).
- **`suspended`:** a checkpoint exists, there is no container, and the Restore button is shown.
- **`restored`:** terminal. The row links to the session that continued it.
- Both are in `TerminalSession::TERMINAL_STATES`: nothing runs and no slot is held, which is what every reader of that set wants to know.

`Sessions::Suspension.supported?` is true for an `agent_session` in `interactive` mode, owned by a person, where the checkpoint uploader's storage signs uploads (§8).

Today the final state is written by the cleanup activity with `update!`, not through an AASM event (`app/temporal/activities/container/admitted_phase_activity.rb`). `suspended` must be written in the same place, and the AASM events `suspend` / `mark_suspended` / `mark_restored` are added so the model agrees. The scanners that look for dead or stale sessions skip `suspended` and `restored`, which are terminal. `CleanupStaleActivity` gives a `finishing` session with the suspend flag the checkpoint's budget before it calls it stuck.

### 3.2 The 23-hour limit

`ContainerWorkflow#await_signal_if_needed` swallows the timeout (`rescue Timeout::Error → nil`), so the cleanup phase is not told it was a timeout. The cleanup activity works it out from the session instead (`Sessions::Suspension.time_limit_reached?`): an interactive session that reaches cleanup with no error, no finish asked for, and `ready_at` within 30 minutes of the limit was ended by the limit. Every other way an interactive session ends carries an error (a dead container, contact loss, a revoked membership) or a finish.

So the workflow code does not change, and no Temporal patch is needed: a workflow already running when the release lands is suspended at its limit like a new one.

### 3.3 The Suspend button

**Suspend** on the session page and in the sessions list, for the owner, while the session is `running` or `ready`. API: `POST /api/v1/terminal_sessions/:id/suspend`.

It goes the same way as Finish: `SessionService.suspend` records `suspend_requested_at`, moves the session to `finishing` and sends the same `container_finished` signal. The cleanup activity reads the request off the session.

### 3.4 What suspend still does

The suspend branch is the normal cleanup minus one step:
- Logs, terminal output and usage are collected.
- Refreshed credentials are written back.
- **Outputs are not turned into assets.**
- The checkpoint is taken and uploaded **before** the container is deleted.

If the checkpoint fails (upload refused, archive over the cap, timeout), the session falls back to the normal finish: outputs become assets and the state is `finished`. The failure is recorded in `metadata.suspend_error`. A suspended row without an archive must never exist.

## 4. The checkpoint

### 4.1 The archive

One `tar.gz` per suspended session (gzip, so the expiry sweep can read it with Ruby's own `Zlib` and `Gem::Package::TarReader`). `Sessions::Checkpoint` writes one bash script that builds it inside the container and uploads it with a presigned PUT, as `Sessions::LogCollector` uploads logs, then records the manifest from what the script printed.

```
manifest.json
workspace/          /workspace, except the paths below
conversation/       the CLI's conversation files, relative to $HOME
repos/<key>/        per repository: head.bundle, tracked.patch, untracked.tar
```

Left out of `workspace/`:
- `repo/`, which is handled per repository;
- `assets/`, restored from the session;
- `.mcp.json` and `.aixle/`, which hold secrets and are provisioned fresh, and `_bmad/`, which is installed again;
- the agent's context file when it lives in `/workspace` (Cursor's `AGENTS.md`), which the new session writes again;
- rebuildable directories at any depth: `node_modules`, `.venv`, `venv`, `__pycache__`, `.next`, `.turbo`, `.cache`, `.gradle`, `target`, `dist`, `build` (`Sessions::Checkpoint::REBUILDABLE_DIRS`). The manifest records what was left out.

**Cap.** The cap is 2 GB compressed. If the full archive would exceed it, `workspace/` is dropped and the rest is kept. The conversation and the git work are small and matter most. The manifest records what was dropped and the session page says so.

**Storage.** The archive is stored unmasked: Cursor and Antigravity keep their conversation in SQLite, and masking would corrupt it. It sits under a private prefix with server-side encryption, is read only by the restore path, and is deleted at restore expiry.

### 4.2 The conversation

Each adapter declares where its conversation lives and how to find its id. Paths from the probe:

| Runtime | Conversation files | Id from |
|---|---|---|
| Claude Code | `~/.claude/projects/` | `projects/-workspace/<id>.jsonl` |
| Codex | `~/.codex/sessions/`, `~/.codex/session_index.jsonl` | the rollout file name |
| Copilot CLI | `~/.copilot/session-state/` | the directory name |
| Cursor | `~/.cursor/chats/` | the directory name under the workspace hash |
| Gemini CLI | `~/.gemini/tmp/workspace/` | `sessionId`, first line of the chat file |
| Grok | `~/.grok/sessions/%2Fworkspace/` | the directory name. `memory-v2/` is left out |
| Antigravity | `~/.gemini/antigravity-cli/{conversations,brain}/`, `cache/last_conversations.json` | `last_conversations.json["/workspace"]` |
| Kiro | `~/.kiro/sessions/`, `~/.kiro/session-index/` | the `sess_<id>` directory name |

If there are several conversations, the most recently written one is taken. Login files, settings and indexes are not saved, because the new session writes its own.

### 4.3 Repositories

For each checkout in `metadata.repository_paths`, the script records:
- `branch` (`git symbolic-ref --short HEAD`, or none when detached);
- `head_sha`;
- whether the branch exists on the remote (`git ls-remote --heads origin <branch>`; the session's credential helper is still in place at this point);
- `dirty`.

It then writes:
- `head.bundle`: `git bundle create head.bundle --branches --not --remotes`, the commits on local branches that no remote ref has. Git refuses an empty bundle; that case is recorded as "nothing unpushed".
- `tracked.patch`: `git diff --binary HEAD`, staged and unstaged changes together.
- `untracked.tar`: the files listed by `git ls-files --others --exclude-standard -z`, so ignored files stay out.

**Restore** of each repository:
1. Clone the recorded branch if the remote has it, otherwise the repository's `source_branch`. This is the same blobless clone as today, with a branch argument.
2. `git fetch head.bundle 'refs/heads/*:refs/heads/*'`, then `git checkout <branch>` and `git reset --hard <head_sha>`.
3. `git apply --binary tracked.patch`, then extract `untracked.tar`.

Probed before the code, in the agent image against a real repository (2026-11-20): a bundle fetch works on a blobless clone, with an unpushed commit on the cloned branch and a new local branch both restored. The fetch refuses to update the checked-out branch, so the restore detaches HEAD first. The generated checkpoint and restore scripts were then run end to end in the image: branch, head, unpushed commits, uncommitted and staged changes, untracked files, `outputs/`, other files under `/workspace` and the conversation all came back.

If the bundle does not apply, it is left at `/workspace/.aixle-restore/<key>.bundle` and the restore notice says so. The work is still there for the agent or the person to recover by hand.

### 4.4 The manifest

```json
{
  "version": 1,
  "session_id": 1234,
  "agent_type": "claude_code",
  "cli_version": "2.1.318",
  "conversation_id": "eb395f2d-…",
  "suspended_at": "2026-11-20T10:00:00Z",
  "reason": "time_limit | user",
  "repos": [{ "repository_id": 7, "path": "repo/api", "branch": "feature/x", "head_sha": "…",
              "on_remote": false, "dirty": true, "bundle": true, "patch": true, "untracked": true }],
  "workspace": { "included": true, "excluded": ["node_modules", "…"], "bytes": 12345 },
  "bytes": 23456
}
```

## 5. Restore

### 5.1 Who and where

- **Who:** the owner only. The same rule as Finish (`current_user.terminal_sessions`).
- **Where:** a Restore button on suspended sessions in the sessions list and on the session page.
- **API:** `POST /api/v1/terminal_sessions/:id/restore`. A personal MCP tool can follow later.

### 5.2 The new session

1. Copy the configuration into a new `TerminalSession` with `restored_from_session_id`:
   - agent, model and effort;
   - session config and metadata, `aixle_builder` included;
   - linked repositories, assets, tools, skills, MCP servers and config items.

   Validation, preflights and admission run as for any session. A resource that has since been archived or detached is left out and listed in the restore notice. A missing agent credential stops the restore with the usual error.
2. The old row stays `suspended` until the new session reaches `running`, then becomes `restored`. A restore that fails at launch can be tried again.
3. Provisioning is the usual pipeline, with two changes:
   - Repositories are set up from the manifest (§4.3) instead of a plain clone.
   - After provisioning and before the CLI starts, the archive is downloaded inside the container with a presigned GET, the way assets are, and unpacked: `workspace/` over `/workspace`, `conversation/` into `$HOME`.
4. The CLI starts with the adapter's resume command (§5.3). A restore notice goes into the context file (§5.4). What the restore did is kept in `metadata.restore` (`resume`, `conversation_id`, `notes`); `Sessions::Restore.launch_command` reads it when the CLI is started.

### 5.3 Resume command

A new adapter method, `resume_command(conversation_id, mode:)`, is the adapter's own `session_command` plus the resume flag. It also keeps everything the launch needs, such as Copilot's `COPILOT_GITHUB_TOKEN="$(cat …)"` prefix: without it the history loads but the CLI asks for `/login`.

| Runtime | Flag |
|---|---|
| Claude Code | `--resume <id>` |
| Codex | `resume <id>` (subcommand, after the global flags) |
| Copilot CLI | `--resume=<id>` |
| Cursor | `--resume=<id>` |
| Gemini CLI | `--resume <id>` |
| Grok | `--resume <id>` |
| Antigravity | `--conversation=<id>` |
| Kiro | `--resume-id <id>` |

**Fallback.** The CLI starts fresh and the conversation files are left in `/workspace/.aixle-restore/conversation/`. This happens when:
- the adapter has no resume command;
- the manifest's `cli_version` differs from the pin the new session runs. Stores are internal formats, and an upgrade may not read them;
- the conversation id is missing.

The notice tells the agent where the files are. Codex also needs the same OpenAI organization as the original login; restore uses the same user's credential, which is that login unless the user signed in to another account since.

### 5.4 Restore notice

The notice is a section of the context file, not typed into the conversation. It says:
- which session this continues, and when it was suspended;
- that running processes are gone, and that packages and files outside `/workspace` are not restored;
- what was not restored: a dropped `workspace/`, a bundle that did not apply, missing resources, a fresh conversation.

A restored session can itself be suspended and restored again.

## 6. Expiry and notifications

- **On suspend:**
  - set `suspended_at` and `restore_expires_at = suspended_at + 30 days`;
  - email the owner: which session, why (time limit or their own Suspend), and the date until which it can be restored, with a link;
  - pattern after `AgentCredentialMailer` / `TeamMailer`.
- **Reminder:** three days before expiry, unless the session was restored.
- **Sweep:** a daily Temporal cron, alongside `StaleSessionCleanupWorkflow`. It takes each `suspended` session past `restore_expires_at` and:
  1. turns `workspace/outputs/` from the archive into assets, as a normal finish would have done;
  2. deletes the archive;
  3. sets the state to `finished` with `metadata.suspend_expired = true`.

  Step 1 keeps a forgotten suspended session from losing the outputs a finished one would have kept. If this is not wanted, it can be dropped.
- **On restore:** the archive is kept until the original expiry date. A failed restore can be retried, and the restored session's own suspend writes a new archive. The sweep deletes the old one on schedule.

## 7. Data model

**`terminal_sessions`:**
- `state` gains `suspended` and `restored`. The column is a string, so there is no enum migration.
- `restored_from_session_id`: a nullable foreign key to `terminal_sessions`. Deleting the old row nullifies it.
- `suspended_at` and `restore_expires_at`: nullable datetimes, indexed for the sweep.

**`session_checkpoints`** (one per suspended session):
- `terminal_session_id`, unique, with `on_delete: cascade`;
- `archive_data`: Shrine on the store bucket, under a private prefix;
- `byte_size` and `manifest` (jsonb).

A separate table keeps the archive's lifecycle (upload, retention, deletion) out of the session row, and leaves room for checkpoints taken while a session runs (§11).

Deleting a user or a project deletes their checkpoints and archives with them. The cascades on `terminal_sessions` already cover the rows; the files need a Shrine deletion hook.

## 8. Runtimes and storage

The archive goes from the container straight to S3-compatible storage with a presigned PUT, and comes back with a presigned GET.

- **Hosted Docker and Kubernetes:** supported.
- **External runners with S3-compatible storage:** supported. The runner protocol's 1 MiB inline cap (`ContainerRuntime::RunnerRuntime#read_file_result`, runner `PROTOCOL.md` §6.5) only limits files read back through the runner, and the archive does not go that way.
- **A deployment without S3-compatible storage:** `Sessions::Suspension.supported?` is false and sessions finish as today. This is the case the 1 MiB cap comes from: a larger file cannot be read at all.
- **Runner with a reused volume:** a restored session may land on a machine whose volume still holds an older checkout. That needs the fetch-and-reset path the code does not have yet (research report §6). Until then, a restore on such a runner clones into a fresh path.

## 9. UI

- **Sessions list:**
  - a **Suspended** status with the days left ("Suspended · 27 days to restore") and a **Restore** button for the owner;
  - **Restored** links to the session that continued it;
  - a filter for suspended sessions.
- **Session page:**
  - **Suspend** next to Finish while the session runs;
  - for a suspended session: Restore, the expiry date, and what was saved and left out, from the manifest;
  - a restored session shows "Continued from #N".
- **Warning before the limit:** an hour before the 23-hour limit, a banner on the live session: "This session will be suspended in about an hour; you can restore it within 30 days."

## 10. Plan

All phases were built in PR #802:

| Phase | Content | Where |
|---|---|---|
| 0 | Bundle round trip on a blobless clone; the generated scripts run end to end in the agent image | §4.3 |
| 1 | States, columns, `session_checkpoints`, `Sessions::Suspension`, scanners | migration `20261120100000`, `TerminalSession`, `CleanupStaleActivity` |
| 2 | Checkpoint script and manifest, fallback to finish, adapter `conversation_paths` / `conversation_id_command` / `resume_arguments`, Suspend API and buttons | `Sessions::Checkpoint`, `AgentSessionStrategy#before_cleanup`, `AdmittedPhaseActivity` |
| 3 | Restore API and buttons, configuration copy, restore script, resume command and fallback, restore notice | `SessionService.restore`, `Sessions::Restore` |
| 4 | Hourly sweep with outputs to assets, emails, the warning before the limit | `Sessions::SuspensionExpiry`, `SuspendedSessionExpiryWorkflow`, `SessionMailer` |

Still to check live on a deployment with S3: a suspend at the real 23-hour limit, and a restore of each CLI through the product rather than by hand.

## 11. Out of scope

- Checkpoints while a session runs, for containers that die. The `session_checkpoints` table leaves room for them.
- Restoring as another person (handoff) and live sharing. See the research report §4–5.
- Pinning asset versions at injection.
- Workflow steps: retry already exists for them.
- Anything outside `/workspace`: global installs, caches, `/tmp`, running processes.

## 12. Where the build differs from the proposal

- **No `suspending` state.** Saving happens in `finishing` (Suspend) or `ready` (the limit); §3.1.
- **No change to the Temporal workflow.** The limit is recognised from the session in the cleanup activity; §3.2.
- **`tar.gz`, not zstd**, so the expiry sweep can read it without a native library; §4.1.
- **Workflow steps are left out.** A run waits on its interactive step with its own 23-hour limit (`WorkflowExecutionWorkflow::INTERACTIVE_TIMEOUT`) and then treats the step as failed. Suspending a step would mean holding the run open for 30 days, relinking `step_run` to the restored session, and deciding what cancel and retry do meanwhile. The checkpoint and restore are session-level, so steps can be added without changing them.
