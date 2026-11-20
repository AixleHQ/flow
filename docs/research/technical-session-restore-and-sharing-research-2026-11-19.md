# Session restore and session sharing: research

Date: 2026-11-19. Status: research only, nothing decided or built. Conversation resume was probed live on staging for all eight CLIs (§3.3).

Origin: customer feedback on 2026-11-16 asked for two things for long interactive work (shaping a PRD, exploring code):

- **Restore.** Pick up an ended interactive session where it stopped: the agent's conversation and everything in `/workspace`.
- **Share.** Let a chosen person or a project team join a live interactive session and type into it, not only watch.

This report says what the platform does today, what each feature would take, and where the hard limits are. Paths are relative to the repository root. "(inferred)" marks a reading of the code that was not confirmed by running it. Nothing here was tested live.

## 1. Summary

**Restore.** The platform keeps nothing a restore could use.
- When a session ends, the container and everything in it is deleted. The only exception is `/workspace/outputs`, which becomes assets.
- Work the agent did not push is lost.
- The branch and commit of each repository are not recorded.
- Only three of the eight CLIs have their conversation collected, and it is stored masked and sometimes cut off.

Restore can be built for the parts the platform owns:
- **Repositories:** branch, commit, unpushed commits, uncommitted and untracked files.
- **Assets and outputs.**
- **The rest of `/workspace`.**
- **The conversation:** checked live for Claude Code, Codex, Cursor, Copilot CLI, Gemini CLI, Grok and Antigravity. In a fresh container each one resumed by id and recalled the earlier exchange. Copying the CLI's own conversation files was enough; logins, settings and indexes were not needed. Kiro loaded its history but could not answer: the account had used up its monthly quota.

It cannot bring back anything outside `/workspace`: global installs, caches, `/tmp`, or running processes such as a dev server. It cannot bring back a container that died before anything was saved, unless checkpoints are also taken while the session runs.

**Sharing with control.** Today only the owner can type, and the server enforces it. Everyone else gets a read-only terminal, and only if the owner turned on "share active sessions" in their profile. That setting covers every session they own; there is no share with a specific person or team.

The terminal is a full shell in a container that holds the owner's identity:
- agent subscription and login files;
- personal MCP tokens;
- a token that acts as the owner on GitHub;
- the MCP key that acts as the owner in Aixle;
- config-item secrets.

The live terminal is not masked. Sending the agent messages instead of keystrokes does not change this: the agent runs with permission prompts off, so a request to print a credential file gets answered. **A "control" share therefore hands the owner's identity to someone else.** It can be built as an explicit, revocable delegation with an audit trail. Whether another person may use someone's personal agent subscription this way is for legal to assess.

The two features connect: a restore performed by another person is a handoff that runs on that person's own credentials (§5).

## 2. The platform today

### 2.1 Interactive sessions and how they end

Interactive sessions come from:
- **The new-session form or API:** an `agent_session` (`app/frontend/shared/components/SessionNewForm.tsx:249`, `app/controllers/api/v1/terminal_sessions_controller.rb:25`).
- **Aixle Builder:** an `agent_session` with `metadata.aixle_builder` (`app/controllers/web/company/projects/aixle_builder_controller.rb:31-43`).
- **Workflow steps that are not marked non-interactive** (`app/services/session_service.rb:241`, `app/services/session_config_resolver.rb:153-161`). Chat starts runs, so it produces these too.

How a session ends:

| End | What happens |
|---|---|
| Finish (UI, API, Builder, MCP `stop_session`) | `finishing`, then cleanup (`app/services/session_service.rb:53-75`) |
| 23 hours | The exec phase waits up to `signal_timeout: 82_800` s (`app/services/container_strategies/agent_session_strategy.rb:46`), then cleans up and ends `finished` |
| Container dies, runner loses contact, membership revoked, project moved | `failed` or `cancelled`. If the container is gone, nothing is collected (`app/temporal/activities/container/admitted_phase_activity.rb:137`) |
| Tab closed | Nothing ends. ttyd re-attaches to the same tmux session |
| Idle | No watchdog. `Sessions::Monitor` only visits workflow steps (`app/services/sessions/monitor.rb:39-43`) |
| Agent login refused | Paused (`app/services/sessions/auth_pause.rb:54-71`). An interactive session is only un-paused, never typed into. (inferred) It waits for the 23-hour limit |

Cleanup runs in this order: collect, delete the container, set the final state (`admitted_phase_activity.rb:137-146,248-282`). It has a 120-second budget (`agent_session_strategy.rb:47`).

### 2.2 What is in the container

`/workspace` is the image's working directory. `repo/` and `outputs/` are created at build time (`docker/base/Dockerfile:304`).

| Path | What it holds |
|---|---|
| `/workspace/repo/<name>` | Checkouts. The path map is saved in `metadata.repository_paths` (`app/services/repository_workspace_path.rb`) |
| `/workspace/assets/<folder>/<name>` | Input assets, downloaded at their latest version (`app/services/session_context_service.rb:525-554`). Steps also get upstream outputs and `webhook-payload.json` here |
| `/workspace/tracker/<issue>/` | Tracker attachments (`app/services/trackers/workspace.rb:5-7`) |
| `/workspace/outputs` | Declared outputs, collected at the end |
| `/workspace/.mcp.json` (Claude), `/workspace/.aixle/` | MCP config with resolved bearer tokens; the git credential helper |
| Agent home (`/home/claude`, `~/.codex`, …) | Login files, the context file, skills, the CLI's conversation store |
| `/tmp`, `/var/log` | The prompt file, terminal output, pasted images, context and proxy logs |

The storage underneath depends on the runtime:
- **Hosted Docker and Kubernetes:** no volumes; `/workspace` is the container's own filesystem and goes with it (`app/services/container_runtime/docker_runtime.rb:49-54`, `kubernetes_runtime.rb:559-583`).
- **External runners:** a named volume per machine. With the `reuse` policy, checkouts outlive the session but are changed by the next one (`runner/internal/docker/scrub.go:39-68`).
- **Coder workspaces** used through the `coder_*` tools are outside the session altogether.

### 2.3 What survives a session

| Kept | Where | Usable for restore? |
|---|---|---|
| Session row: config, model, linked assets, repositories, tools, skills, MCP servers, config items (`app/models/terminal_session.rb:153-161`) | DB | Yes, as the recipe for a new session. It points at live rows, not versions (`app/services/versions/launch_record.rb:4-24`) |
| Repo path map | `metadata.repository_paths` | Yes |
| Repo branch and commit | Not recorded | — |
| Unpushed commits, uncommitted and untracked files | Deleted with the container. No auto-commit or WIP push exists | — |
| Which asset versions were injected | Only asset ids are logged (`session_context_service.rb:176`) | Partly |
| Outputs | `Asset` (`pending_review`, folder `session-<id>`) for a standalone session; `WorkflowRunAsset` for a step (`agent_session_strategy.rb:383-441`, `workflow_step_strategy.rb:66-127`) | Yes |
| Conversation | Claude `~/.claude/projects/*/*.jsonl`, Copilot `events.jsonl`, Kiro session files, collected as `SessionLog`. Masked; the fallback path keeps only the last 4 MB (`app/services/sessions/log_collector.rb:45`). Nothing for Codex, Gemini, Cursor, Grok, Antigravity | Not as stored |
| Terminal output | Redacted ANSI stream; replay serves the last 2 MB | No |

### 2.4 Viewing and typing today

- **Visibility rule.** `TerminalSession#visible_to?` answers from two settings on the owner: `share_active_sessions` (default off) and `share_completed_sessions` (default on) (`app/models/terminal_session.rb:369-376`, `db/schema.rb:2230-2231`). A viewer must also reach the project. Admins get no override.
- **Two terminals per container.** Each runs ttyd over the same tmux session (`docker/base/entrypoint.sh:146,153`):
  - `tty` (`ttyd -W`) is writable.
  - `view` (`ttyd -R`, `tmux attach -r`) is read-only.
- **Server-side gate.** Traefik ForwardAuth calls `Api::V1::Internal::WsAuthController`. `OWNER_ONLY_SURFACES = %w[tty ide upload]` returns 403 to anyone but the owner (`app/controllers/api/v1/internal/ws_auth_controller.rb:36-42`). The browser's `readOnly` flag is only a convenience.
- **Access tokens.** A `ContainerTicket` per viewer and session lasts 10 minutes and is traded for a 12-hour cookie on that session's path (`app/services/container_ticket.rb`). (inferred) ForwardAuth runs once per websocket upgrade, so turning sharing off does not close a socket that is already open.
- **Grants.** No per-session share or grant table exists. The nearest patterns are `project_collaborators`, `project_teams` / `project_team_members` and `act_as_consents`.
- **Audit.** Input is not logged anywhere: `pipe-pane` records output only. ForwardAuth logs refusals only. An `audits` table exists for hand-written events (`app/models/audit.rb`).
- **Notifications and presence.** No in-app notifications and no "who is watching". `TeamMailer` is the email pattern to copy.

## 3. Restore

### 3.1 Scope

Restore covers interactive sessions: the new-session form and Aixle Builder. Workflow steps already have retry, which starts the step fresh.

A restore creates a **new session** with `restored_from_session_id`. It does not revive the old row. It goes through admission, preflights and permission checks like any session. It runs on the restoring user's credentials. Today that must be the owner; see §5 for anyone else.

### 3.2 Piece by piece

Following the proposal: repositories by branch, assets by which were added, outputs saved.

**Repositories.** A branch name alone is not enough: the agent's commits may never have been pushed, and some work is not committed at all. At checkpoint, per checkout:
- **Record** the remote, the branch, the base commit the session started on, the head commit, and whether the tree is dirty.
- **Save** a `git bundle` of commits not reachable from the remote, `git diff --binary HEAD` for tracked changes, and a tar of untracked files that are not ignored (`git ls-files --others --exclude-standard`).
- **Skip** ignored files (`node_modules`, build output). They are large and can be rebuilt; the restored agent is told to rebuild them.

On restore: a blobless clone of the recorded branch (as today, `app/services/git_credentials/session_git_setup.rb:68`), then fetch from the bundle, check out the head commit on the branch, apply the patch and extract the untracked files.

New code is needed in two places:
- The clone takes only the repository row's current `source_branch`, so a branch the agent created has to come from the bundle. If that branch was pushed and later deleted, the bundle still has the commits.
- On a runner with a reused volume the checkout already exists. The code has no fetch-and-reset path, even though `docs/design/agent-runtimes/DESIGN.md` describes one.

The alternative is a WIP push to a hidden ref in the customer's repository. Tracker attachments already do this on `refs/aixle/attachments/…` (`docs/design/tracker-attachments.md` §11.2). It needs no storage on our side, but it writes to the customer's remote, needs push access, and depends on the host. Prefer the bundle, which stays in our storage.

**Assets.** At injection, record which asset versions were placed and where. On restore, place the same versions; `AssetVersion` history exists. Copies the agent edited in `/workspace/assets` are covered by the workspace archive below.

**Outputs.** Already stored. On restore, copy them back into `/workspace/outputs`. Today they are left out of later sessions: the Builder's asset picker lists only `active` assets (`aixle_builder_controller.rb:25`), and these are `pending_review`.

**The rest of `/workspace`.** Tracker files, scratch files and drafts the agent wrote outside `repo/`: one tar of `/workspace` with these left out:
- `repo/`, handled above;
- `.mcp.json` and `.aixle/`, which hold secrets and are provisioned fresh;
- ignored-style directories such as `node_modules`, `.venv` and build output, by a fixed list.

It needs a size cap. Pods have no ephemeral-storage limit, and cleanup has 120 seconds.

**Conversation.** Copy each CLI's store from its home directory, leaving its login files out, and resume by id (§3.3). Two choices:
- **Masked or raw.** The collected transcripts are masked: secret values become markers. A masked transcript keeps the conversation but drops secret values the agent saw; it can fetch them again through its tools. A raw copy is exact but puts live secrets into storage. Prefer masked.
- **What the probe showed.** For Claude Code and Copilot, the `SessionLog` the platform already collects was byte-identical to the file in the container (same SHA-256). For a conversation with no secret in it and under the 4 MB cut, the conversation half of restore can come from what is stored today.
- **Not yet shown:** that a transcript with masked values still resumes. Codex stores encrypted reasoning, and Copilot's `events.jsonl` replays in full, so a masking marker inside either could matter.
- **No truncation.** The 4 MB fallback cut has to go for these files, and the Claude glob has to include nested subagent transcripts. Today `projects/*/*.jsonl` is one level deep.

**Outside `/workspace`.** Global installs, `~/.cache`, `/tmp`, files the agent wrote into its home directory, and running processes are not restored. This is the hard limit raised in the earlier discussion: an agent can write anywhere.

Two mitigations, neither complete:
- The context file tells every interactive session to keep its work under `/workspace`, because nothing else survives.
- The first message after a restore tells the agent it is in a restored session: processes are gone, packages outside the repo have to be reinstalled, files outside `/workspace` are lost.

### 3.3 Agent CLIs

Pinned versions come from `config/agent_runtimes.json`. Every CLI keeps its conversation on local disk under the agent's home directory, and every CLI has a resume-by-id flag. Our containers always use the same home directory and the same working directory (`/workspace`), so path-keyed stores line up in a new container. The table below is from documentation and code; the live probe that follows it confirms or corrects it for all eight.

| Runtime (pin) | Conversation store | Resume | Works in a new container? |
|---|---|---|---|
| Claude Code 2.1.318 | `~/.claude/projects/-workspace/<id>.jsonl` | `claude --resume <id>` | Yes (documented; probed). Collected today, masked |
| Codex 0.166.0 | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` plus a SQLite index, rebuilt at start | `codex resume <id>` | Yes, on the same OpenAI organization: reasoning is encrypted per organization, and another account fails with `invalid_encrypted_content` |
| Gemini CLI 0.60.0 | `~/.gemini/tmp/<slug>/chats/*.jsonl` plus `~/.gemini/projects.json` | `gemini --resume <uuid>` | Yes (probed). The slug for `/workspace` is `workspace` in every container |
| Copilot CLI 1.0.108 | `~/.copilot/session-state/<id>/` plus `session-store.db` | `copilot --resume[=<id>]` | Yes. `events.jsonl` is collected today. Very large files (~512 MB) fail on resume |
| Kiro 3.0.0 | `~/.kiro/sessions/<hash>/sess_<id>/messages.jsonl` plus `~/.kiro/session-index/` (probed; not SQLite) | `kiro-cli chat --resume-id <id>` | History loads (probed); recall unverified. `--cloud` sessions resume from any machine but change how we launch |
| Grok 1.0.70 | `~/.grok/sessions/%2Fworkspace/<id>/` (`chat_history.jsonl`, `updates.jsonl`, `summary.json`) | `grok --resume <id>` | Yes (probed) |
| Cursor 2026.10.22 | `~/.cursor/chats/<hash>/<chatId>/store.db`, undocumented SQLite | `agent --resume=<chatId>` | Yes (probed). The CLI prints the chat id on exit |
| Antigravity 1.5.0 | `~/.gemini/antigravity-cli/conversations/`, undocumented | `agy --conversation <id>` | Unknown. `-c` checks a backend; resume bugs were fixed after our pin |

**Live probe, staging, 2026-11-19.** Each CLI ran as an interactive session through the normal API, on the Kubernetes runtime and the pinned images:

1. Tell the agent a code word and ask it to create `/workspace/notes/probe.txt`.
2. Quit the CLI. Archive the CLI's conversation directory, and `/workspace` without `repo/`, `.mcp.json` and `.aixle/`.
3. Finish the session, so its pod is deleted.
4. Start a new session of the same runtime for the same user. Extract both archives, quit the CLI the session started, and launch it again with the adapter's flags plus the resume flag.
5. Ask "Without running any tools: what code word did I give you earlier, and what path did you create?"

| Runtime | Copied | Resume command | Result |
|---|---|---|---|
| Claude Code | `~/.claude/projects/` | `claude --resume <id>` | Recalled the word and the path. No "Resume this conversation?" dialog (API-billed login; the dialog is reported for Pro/Max) |
| Copilot CLI | `~/.copilot/session-state/<id>/` only; `session-store.db` not needed | the adapter's command with `--resume=<id>` | Recalled. Started without the adapter's `COPILOT_GITHUB_TOKEN="$(cat …)"` prefix, it loaded the history but asked for `/login`. The AI-credit counter continued from the old session |
| Codex | `~/.codex/sessions/…/rollout-*.jsonl` and `session_index.jsonl`; none of the SQLite files | `codex --yolo -c projects./workspace.trust_level=trusted resume <id>` | Recalled. Same user and same OpenAI account, so the cross-organization failure was not exercised |
| Cursor | `~/.cursor/chats/` (`store.db`, `meta.json`) | `agent --force --disable-auto-update --resume=<id>` | Recalled. The chat directory is keyed by a hash that was the same in both containers |
| Kiro | `~/.kiro/sessions/` and `~/.kiro/session-index/` | `kiro-cli --v3 chat --trust-all-tools --trust-workspace --resume-id <id>` | History loaded. The model never answered: the account had reached its monthly limit, so recall is unverified |
| Gemini CLI (API key) | `~/.gemini/tmp/workspace/` (`chats/session-*.jsonl`); `projects.json` was already `{"/workspace": "workspace"}` in the new container, so it did not need copying | `gemini --yolo --resume <sessionId>` | Recalled. On exit Gemini prints only `gemini --resume` (latest); the session id is the first line of the chat file |
| Grok | `~/.grok/sessions/%2Fworkspace/<id>/` only. Not `session_search.sqlite`, and not `memory-v2/`, where Grok had also saved the code word as a memory topic | `grok --yolo --minimal --resume <id>` | Recalled, with its own memory left behind, so the answer came from the conversation |
| Antigravity | `~/.gemini/antigravity-cli/conversations/<id>.db`, `brain/<id>/` and `cache/last_conversations.json` | `agy --dangerously-skip-permissions --conversation=<id>` | Recalled the word and the file, on the platform's own Google login. An earlier attempt on a free Gemini API key loaded the history but every request timed out |

What the probe settled:
- **The id is known.** Every probed CLI except Gemini prints the resume id when it exits (Grok: `grok --minimal --resume <id>`) (`To resume this session: agent --resume=…`, `Resume with: kiro-cli --resume-id …`), and the id is also in the stored file names. This includes Cursor, where the documentation suggested no way to get the id.
- **One directory per CLI is enough.** Logins, settings and SQLite indexes are written fresh by the new session and do not need to be carried over.
- **The adapter builds the resume command,** not a generic wrapper. Each CLI needs the same flags and the same environment as at launch.

Caveats:
- **Claude.** On Pro, Max and Ultra plans Claude Code can show "Resume this conversation?" after a long break or a model change, and the dialog waits for a key. In an interactive session the user answers it. Anything automated would stall on it.
- **Claude and Gemini** delete conversations after 30 days by default. That does not matter if we restore from our own copy.
- **Codex** needs its sandbox and trust overrides passed again on `resume`.
- **Upgrades.** Every store is an internal format. A CLI upgrade between checkpoint and restore can break resume. Record the CLI version in the checkpoint, and say so when it differs.

### 3.4 When to checkpoint

- **At cleanup**, before the container is deleted. This covers Finish and the 23-hour limit, the two ways an interactive session normally ends. `before_cleanup` already collects logs and outputs there and uploads straight from the container with presigned URLs (`app/services/sessions/log_collector.rb`). The checkpoint is one more upload on the same path, within the same 120 seconds, so it needs a size cap.
- **During the session**, for containers that die: OOM, a lost node, runner contact loss. A checkpoint after each agent turn, or every N minutes, is the only cover. The turn-end detector exists, but the monitor visits only workflow steps today. This is a second phase.
- **Ahead of the 23-hour limit**, warn the user and checkpoint before it hits. This is useful even without restore.

### 3.5 The restore path

A "Restore" action on a finished interactive session that has a checkpoint:

1. Copy the old session's configuration into a new session with `restored_from_session_id`. Re-check that each resource still exists and is not archived, that the user still has access, and that the agent credential is the same user's.
2. Provision as usual: credentials, MCP, skills, context file.
3. Restore in this order: repositories, then assets at the recorded versions, then the `/workspace` archive, then outputs, then the CLI store.
4. Launch the CLI with the adapter's resume command. This is a new per-adapter capability, and adapters that cannot resume declare so.
5. Send the restored-session notice as the first message.

Retention: a checkpoint is kept for a fixed period (for example 14 or 30 days) and is deleted with the session. It is encrypted at rest and readable only through the restore path.

### 3.6 Risks

- **Secrets in the archive.** The agent can write secrets into files under `/workspace`, such as `.env` files or tokens it fetched. A tar cannot be masked. The archive is restored only to the same user, which is the same exposure as when the session ran, but it now sits in storage for the retention period.
- **Size.** Monorepos with large untracked trees, data files and model weights. Cap it, and say what was left out.
- **Silent partial restore.** Each part (repo, assets, archive, conversation) can fail on its own. The restored session has to show what came back and what did not, and the agent's notice has to say the same.
- **A different model or CLI version than the original.** Show it to the user.
- **Runtime differences.** Hosted Docker and Kubernetes behave alike. A runner with a reused volume needs the fetch-and-reset path. Coder workspaces are out of scope.

### 3.7 Phases and rough size

| Phase | Content | Size |
|---|---|---|
| 0 | Live probes. Done for Claude, Copilot, Codex, Cursor, Gemini, Grok and Antigravity; Kiro loaded history only. Left: recall on Kiro (quota), Kiro with quota, a transcript with masked values, a Claude subscription login (the resume dialog), and a Codex resume under a different OpenAI organization | Small |
| 1 | Record each repository's branch, base commit, head commit and dirty state, plus the injected asset versions. Useful for audit even without restore | Small |
| 2 | Checkpoint at cleanup: per-repository bundle, patch and untracked files; the `/workspace` archive; CLI stores without truncation; a `SessionCheckpoint` record with retention | Medium |
| 3 | Restore path, per-adapter resume capability, "Restore" in the UI, restored-session notice, warning before the 23-hour limit | Medium |
| 4 | Checkpoints during the session, for crashed containers | Medium |

## 4. Sharing an interactive session with control

### 4.1 Model

A share is a grant on one session:

```
session_shares
  terminal_session_id
  user_id | project_team_id   (exactly one)
  level: view | control
  granted_by_id, created_at, revoked_at
```

How grants work:
- **Teams** are resolved when the grant is checked, so a member added or removed later gains or loses access. Teams already exist (`docs/design/project-teams.md`).
- **The grantee must reach the project.** For `control`, the grantee must also hold a role that can run sessions; the viewer role cannot, as with `stop_session` (`app/services/personal_tools/stop_session.rb:37-45`).
- **The owner's global settings stay** as the "everyone in the project can watch" switch. A grant adds specific people on top of it.
- **Grant and revoke** are recorded in `audits`, and the grantee gets an email (the `TeamMailer` pattern).

### 4.2 What changes

| Where | Change |
|---|---|
| `TerminalSession#visible_to?` | Also true for an active grant of either level |
| `container_accessible_by?` | Unchanged in shape. It still needs project access |
| `WsAuthController` | `tty` allowed for the owner and for an active `control` grant. `ide` and `upload` decided separately; both are a shell or write files |
| `terminal_session_resource.rb`, `step_run_resource.rb` | Hand out the `tty` URL to `control` grantees, not only to the owner |
| `SessionShowContent` | `readOnly` follows the grant, not `isOwner` |
| New | Share dialog (people and teams, level), the list of who has access, revoke |
| New | Revoke closes open sockets (§4.4) |
| New | Presence: who is connected, and with which level |

### 4.3 What `control` gives the grantee

The grantee acts as the owner. They get:

- **The agent**, running with permission prompts off (`claude_code_adapter.rb:1448`), on the owner's subscription and quota. Usage is billed to the owner's session.
- **A shell.** Quit the CLI and you are at bash. From there:
  - the owner's agent login and refresh files, and cloud credentials;
  - the personal MCP bearer tokens in `/workspace/.mcp.json`;
  - the session's MCP key, which calls Aixle tools with the owner's permissions;
  - a GitHub token that acts as the owner, if the owner consented to `github_user_token`;
  - attached config-item secrets.
- **An unmasked view.** Masking applies to stored logs and the MCP tail, not to the live terminal (`app/services/sessions/secret_redactor.rb:27-30`).

**Typing versus steering.** One idea is to give grantees a message box that sends text to the agent through `Sessions::PaneInput` (`tmux send-keys`), instead of the raw terminal. It has real benefits:
- every message carries its author;
- keystrokes from two people do not interleave;
- the grantee cannot quit to bash.

It does not protect the owner's identity: the agent will run "print `~/.claude/.credentials.json`" and the result shows in the shared view. It also cannot answer the CLI's own dialogs (menus, y/n) without key buttons.

**Neither form is a security boundary.** Choose between them for attribution and usability, and describe `control` to the owner plainly: "they act as you, with your subscription and your access."

### 4.4 Revoke, presence, audit

- **Revoke.** ForwardAuth checks only new connections, so revoking does not close an open socket. Options, simplest first:
  1. Restart the writable ttyd on revoke. Everyone reconnects, and the revoked user is refused.
  2. Shorten the cookie and have the page re-check it.
  3. Proxy the terminal through Rails, so each socket is tied to a user. This is the largest change.

  Option 1 is enough for a first version.
- **Presence.** ForwardAuth already knows the user on each upgrade (`X-User-Id`). Record connect events and show who is connected. Disconnects need a heartbeat from the page.
- **Audit.** Raw keystrokes from several writers on one tmux pane cannot be attributed. Record grants, revokes and connections. If steering messages are added, record them with their author.

### 4.5 Open questions

- Can someone else drive a session that runs on the owner's personal agent subscription? This is for legal to assess, per provider, before `control` ships for subscription-backed runtimes.
- Should `control` be limited to sessions on credentials the company owns rather than a personal subscription? That depends on the legal answer.
- When B's input causes spend, it is attributed to A. Is that acceptable, or should a share record that B was connected?
- Workflow-step sessions: are they in scope? Their owner is often the "Runs as" user or a card's assignee, not the person who wants to share.

### 4.6 Phases and rough size

| Phase | Content | Size |
|---|---|---|
| 1 | `view` grants to people and teams: table, `visible_to?`, share dialog, email, audit | Small |
| 2 | `control` grants: WsAuth, URLs, `readOnly`, revoke by ttyd restart, presence, the "acts as you" warning | Medium |
| 3 | Optional steering messages with authors, and key buttons for dialogs | Medium |

## 5. How the two connect: handoff

Once restore exists, "hand this session to a colleague" can be a restore performed by the colleague. It runs on the colleague's own credentials, subscription, tokens and quota, so none of the identity problems in §4.3 apply. It is not live: the owner's session has ended.

Limits:
- **Codex** fails across OpenAI organizations.
- **Other CLIs** carry no account binding in the store, but the colleague's model and plan may differ.
- **Secrets the original agent wrote into `/workspace`** go to the colleague with the archive, so a handoff also needs the owner's consent.

## 6. Side findings

- **An Antigravity login made before the account accepted Google's terms keeps failing.** On staging, a fresh login was first refused with "not currently available in your location". After the same person signed in once through the Antigravity desktop app, the old login was refused with "Client is not eligible for Gemini Code Assist for individuals. Client does not support Google TOS" (`loadCodeAssist`). Logging in again on the platform fixed it with the same pinned `agy` 1.5.0. The error names the client, but the cure was a new login: a user who sees it should accept the terms in the desktop app and reconnect.
- **A stored login went back to an older token.** On staging, after a fresh Antigravity login at 02:34 UTC (token valid to 03:34), the stored credential held the previous token (valid to 03:04) again after an older session that had launched with that token ended (`[AgentSession] Persisted refreshed antigravity_cli credentials` at 02:35:11). Cause: `BaseAdapter#merge_container_credentials` judged only the rotated keys, and Antigravity's `token_expires_at` needs `auth_method`, which is not one of them, so neither token had an expiry and the older one won. Fixed on branch `fix/antigravity-credential-downgrade`.
- **Gemini CLI on Flow takes an API key only.** The Google-account login is deliberately not offered (`app/services/agents/gemini_cli_adapter.rb:40,96`), so a Gemini subscription cannot be used for a probe or a session.
- `app/models/terminal_session.rb:364`: the comment says workflow-step sessions are exempt from the sharing settings. The code has no such branch.
- `docs/design/agent-runtimes/DESIGN.md:2756` says an existing checkout on a reused runner volume "is fetched and reset to the requested ref". The code always clones, and (inferred) a clone into an existing directory lands in `failed_repos`.
- **Copilot CLI** syncs sessions to the user's GitHub account by default (`remoteExport`), and we do not set it. Container sessions are probably appearing in users' GitHub accounts today. (unverified)
- (inferred) **An auth-paused interactive session** waits for the 23-hour limit; pause expiry runs only for workflow steps.
- An earlier research report declined "resume in a new container" for auth expiry, for the same reason this report treats the filesystem as the hard part (`docs/research/technical-graceful-agent-auth-expiry-research-2026-10-08.md` §5).

## 7. Sources

- **Claude Code:** https://code.claude.com/docs/en/sessions.md, https://code.claude.com/docs/en/cli-reference
- **Codex:** https://learn.chatgpt.com/docs/developer-commands?surface=cli. The organization binding: https://community.openai.com/t/codex-app-cannot-resume-session-after-api-key-switch-encrypted-content-organization-id-mismatch/1374803
- **Gemini CLI:** https://geminicli.com/docs/cli/session-management/, and `packages/core/src/config/storage.ts` and `services/chatRecordingService.ts` in google-gemini/gemini-cli
- **Cursor:**
  - https://cursor.com/docs/cli/reference/parameters
  - https://forum.cursor.com/t/local-ide-agent-chats-and-the-agent-cli-still-use-separate-session-stores/165486
  - https://github.com/coder/registry/issues/747
- **Kiro:** https://kiro.dev/docs/cli/chat/session-management/
- **Copilot CLI:**
  - https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference
  - https://docs.github.com/en/copilot/concepts/agents/copilot-cli/chronicle
  - https://github.com/github/copilot-cli/issues/4251
- **Grok:** https://docs.x.ai/build/features/sessions, https://docs.x.ai/build/cli/headless-scripting
- **Antigravity:** https://antigravity.google/docs/cli/commands/resume.md, https://github.com/google-antigravity/antigravity-cli/releases
