# Connecting Coder

Coder connects per Flow project. A connection names one Coder deployment and a
session token for one Coder account. From then on, every session in the
project has the `coder_*` tools: an agent borrows a workspace from a pool,
clones a repository onto it, runs commands there over SSH, and hands it back.
Use it for work that should run on a machine of your own rather than in the
agent's container — a test suite, a build, a `docker compose` stack.

The token stays in Flow. Flow makes every Coder call itself, and the agent's
container never receives the token.

Any member who can change the project connects it; viewers cannot.

---

## Before you connect

- **An account for Flow.** Flow acts as the account the token belongs to and
  uses only the workspaces that account owns: it starts them, creates new ones
  in that account, deletes dead ones, and runs commands on them with
  `coder ssh`. Use an account kept for Flow rather than your own.
- **A pool.** The pool is every workspace the token's account owns whose name
  starts with the connection's machine name prefix, or every workspace it owns
  when there is no prefix. Other people's workspaces are never in the pool,
  even with an admin's token.
- **`git` on the workspaces**, if agents should clone repositories onto them.

## Connecting

1. On the project's **Integrations** page choose **Connect → Coder**.
2. Enter the **Coder URL** (for example `https://coder.example.com`; `http`
   works too) and the **Session Token**.
3. Open **Advanced** for the pool settings:
   - **Default template** — the name of the Coder template Flow creates a new
     workspace from when no workspace in the pool is free. Leave it blank and
     Flow only hands out workspaces that already exist.
   - **Machine name prefix** — which workspaces make up the pool. New
     workspaces are named `<prefix>-<8 hex characters>`, or `aixle-…` without
     a prefix.
   - **Lock TTL (minutes)** — how long a workspace stays with a session after
     the session's last Coder call. The default is 120.
4. Select **Connect**.

Flow checks the token against Coder and names the connection after the
account, for example **Coder (alice)**. The row shows the URL, the template,
the prefix and the lock TTL. A failed check still saves a row, named **Coder
(unverified)** and in status **Error**, and Flow says why.

## Changing the settings

**Edit settings** on the row opens **Coder settings** with the same three
fields. Clearing **Default template** stops Flow creating workspaces. Clearing
**Machine name prefix** widens the pool to every workspace the token's account
owns, and stops Flow deleting dead ones.

The URL and the token cannot be changed in place. Connecting again adds a
second connection instead of replacing the first, so remove the old row
afterwards.

Removing a connection deletes nothing in Coder. It drops Flow's locks, and
sessions in the project lose the tools.

---

## Tools

You do not attach these: every session in a project with an active Coder
connection has them. They also appear as the **Coder** group in the tool
picker (see [Tools](/docs/tools)).

| Tool | What it does |
| --- | --- |
| `coder_allocate_machine` | Takes a workspace from the pool and locks it to the session. `exclude` skips workspaces by name, so a workspace that just failed is not handed back again. |
| `coder_prepare_repo` | Clones one of the session's repositories onto the workspace, or repairs a clone already there. The default path is `/root/<repo name>`. `ref` checks out a branch, tag or commit. Runs detached and returns a `job_id`. |
| `coder_ssh_exec` | Runs a shell command on the workspace and returns the exit code, stdout and stderr. `detach: true` starts it in the background and returns a `job_id`. |
| `coder_job_status` | Reports a detached job's `state`, its `exit_code` once it has finished, and the tail of its log. |
| `coder_release_machine` | Hands the workspace back before the session ends. |

The usual order is allocate, prepare the repository, run commands, release.
`coder_prepare_repo`, `coder_ssh_exec` and `coder_job_status` only work on a
workspace the calling session holds.

### Locks

- One workspace goes to one session at a time. That holds across Flow
  projects too, when their connections reach the same workspaces.
- Every `coder_ssh_exec`, `coder_job_status` and `coder_prepare_repo` call
  renews the lock. After **Lock TTL** minutes without one, the lock lapses and
  another session can take the workspace.
- When a session ends, Flow releases every workspace it still holds.

### Which workspace a session gets

- Flow skips a workspace whose Coder agent reports it disconnected or
  unhealthy. After locking one, it runs a short SSH check. A workspace that
  does not answer within 15 seconds, or whose 1-minute load average is above
  2 × its cores, is left out of the pool for 30 minutes.
- When no free workspace is healthy, or none is free at all, Flow creates one
  from the default template. Without a template, or when creating fails, it
  hands out the least unhealthy free workspace and adds a `health_warning` to
  the result.
- A stopped workspace is started when it is picked, and Flow waits up to 240
  seconds for the build. Flow never stops a workspace.

### Dead workspaces are deleted

Every 10 minutes Flow checks the workspaces that the token's own account owns
under the prefix. A workspace is deleted when, at two checks at least 10
minutes apart:

- Coder says it is running but reports every agent on it disconnected or
  unhealthy, and it does not answer an SSH check; or
- its last start or stop build failed.

Flow never deletes a workspace a session holds, deletes at most three per
check, and deletes nothing for a connection without a prefix. A workspace
whose delete build failed is left alone for you to deal with.

---

## Limits

- `coder_prepare_repo` clones GitHub repositories (see
  [GitHub](/docs/github)) and public ones. GitLab and Azure DevOps
  repositories are refused.
- A foreground `coder_ssh_exec` call ends after 60 seconds by default and
  120 seconds at most. A timeout ends the SSH connection, not the command on
  the workspace. For anything longer, use `detach: true` and poll
  `coder_job_status`.
- One `coder_ssh_exec` call returns at most 256 KiB of output. Anything past
  that is cut, and the result says `truncated: true` and gives the full sizes.
- Flow checks the token only when you connect. There is no connection test
  for Coder, and a token that later expires leaves the row **Active**.
- Keep one Coder connection per project. With two active ones, which one the
  tools use is not defined.
- Coder connections made before integrations moved to projects may be
  company-wide. They show **Company** scope, serve every project that has no
  Coder connection of its own, and cannot be edited from a project page.

---

## Self-hosted

- **The `coder` CLI.** Flow runs `coder ssh` from its own app containers, not
  from the agent containers, so the app containers need a network path to
  Coder. The Flow image ships the CLI for its own architecture, amd64 or arm64
  (build argument `CODER_CLI_VERSION`, default `v2.34.5`). An image built
  without it cannot run commands on workspaces.
- **Private Coder deployments.** Flow refuses a Coder URL that is, or resolves
  to, a private or internal address. It sends API calls to the host's public
  IPv4 address from public DNS. If your Coder is only reachable inside your
  network (split-horizon DNS, a cluster-internal service name), add its
  hostname to `URL_SAFETY_TRUSTED_HOSTS`. That variable takes exact hostnames,
  comma-separated, and only the Coder integration reads it. A private IP
  address in the URL is refused even then.
- **Tuning.** These are optional, and apply to the whole deployment:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CODER_AWAIT_BUILD_TIMEOUT` | `240` | Seconds Flow waits for a workspace to start or be created. |
| `CODER_HEALTH_PROBE_ENABLED` | `true` | `false` turns off the SSH health check. Flow then deletes only workspaces whose last start or stop failed. |
| `CODER_HEALTH_PROBE_TIMEOUT` | `15` | Seconds the SSH health check may take. |
| `CODER_HEALTH_LOAD_FACTOR` | `2.0` | A workspace is unhealthy when its 1-minute load average exceeds cores × this. |
| `CODER_UNHEALTHY_COOLDOWN_MINUTES` | `30` | How long an unhealthy workspace stays out of the pool. |
| `CODER_SSH_EXEC_CEILING_SECONDS` | `120` | Longest a foreground `coder_ssh_exec` call can run. |
| `CODER_SSH_EXEC_INLINE_BYTES` | `262144` | Output one `coder_ssh_exec` call returns. |
| `CODER_JOB_STATUS_TAIL_LINES` | `40` | Log lines `coder_job_status` returns by default. |
| `CODER_REAP_ENABLED` | `true` | `false` stops Flow deleting dead workspaces. |
| `CODER_REAP_CONFIRMATION_MINUTES` | `10` | How far apart the two checks before a deletion must be. |
| `CODER_REAP_MAX_DELETIONS_PER_RUN` | `3` | Most workspaces deleted in one check. |

The template, prefix and lock TTL are set on each connection, not through
environment variables. The full list is in the
[configuration reference](/docs/config-schema).

## When something goes wrong

- **"Coder token verification failed: … HTTP 401"** when connecting — the
  token is wrong or expired. Remove the **Coder (unverified)** row and connect
  again.
- **"Coder URL cannot point to private or internal network addresses"**, or
  **"Coder host … has no public address"** — see *Private Coder deployments*
  above.
- **"No active Coder integration for this project."** from a tool — the
  project has no active Coder connection, or its only one is in **Error**.
- **"… list workspaces failed: … HTTP 401"** from a tool while the row still
  says **Active** — the token expired or was revoked after you connected.
  Connect again with a new token, then remove the old row.
- **`coder_allocate_machine: ExhaustedError: …`** — no workspace could be
  handed out. The message says why: the token's account owns no workspaces
  matching the prefix, they are held by other sessions, they failed to start,
  or they are unhealthy. It ends with why Flow could not add one: no default
  template is set, or "creating a workspace from template … failed" and
  Coder's reason. Free some, add some, or set a default template. A "template
  not found" means the name does not match a template the token's account can
  use.
- **"session does not hold the lock for workspace …"** — the lock lapsed
  after **Lock TTL** minutes without a Coder call, and possibly went to
  another session. Allocate again.
- **"coder ssh: timed out after …"** — the command may still be running on
  the workspace. Do not run it again. Run it with `detach: true` and poll
  `coder_job_status`.
- **"coder ssh: command not found (the coder CLI is missing from the Rails
  image)"** — a self-hosted image without the CLI. See *Self-hosted* above.
- **"coder_prepare_repo: gitlab repositories are not supported yet — only
  GitHub and public clones"** — see *Limits*.
