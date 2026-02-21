# Base Agent Container Image

Base Docker image for AI coding agent containers. Provides ttyd (web terminal), OpenVSCode Server (browser IDE), MITM proxy (request logging), and auth-check service.

## Components

| Component | Port | Session Type | Purpose |
|-----------|------|-------------|---------|
| ttyd | 7681 | all | Web terminal with tmux persistence |
| OpenVSCode Server | 8443 | agent_session | Browser IDE (file tree, editor, search) |
| Auth-check | 4040 | auth_setup | Lightweight `/auth` endpoint |
| MITM proxy | 8888 | all | API request/response logging |

## Resource Limits

### OpenVSCode Server Memory Usage

OpenVSCode Server runs with `--file-watcher-polling` enabled by default (inotify is unreliable across Docker volume types).

| Scenario | Approx. RSS | Notes |
|----------|------------|-------|
| Idle (no workspace open) | ~150-200 MB | Server process + extensions host |
| Small workspace (<1k files) | ~200-280 MB | +10-30 MB polling overhead |
| Medium workspace (1k-10k files) | ~250-350 MB | Typical agent session with cloned repo |
| Large workspace (10k+ files) | ~300-450 MB | Multiple repos, monorepo |

### Recommended Container Memory Limits

| Use Case | Memory Limit | Rationale |
|----------|-------------|-----------|
| auth_setup | 256 MB | ttyd + auth-check only, no IDE |
| agent_session (minimum) | 512 MB | ttyd + VS Code Server + polling |
| agent_session (recommended) | 1024 MB | Headroom for agent CLI (Claude, Codex, etc.) |
| agent_session (heavy workload) | 2048 MB | Large repos, multiple agent tools running |

### inotify Watches

The entrypoint attempts to set `fs.inotify.max_user_watches=524288` at container start. This requires either a privileged container or host-level sysctl configuration. If the write fails, polling mode (`--file-watcher-polling`) covers the gap.

For production Docker hosts, set the sysctl at the host level:

```bash
# /etc/sysctl.d/99-vscode.conf
fs.inotify.max_user_watches=524288
```

Apply with `sysctl --system` or reboot.

### File Watcher Exclusions

VS Code Server is configured to exclude these patterns from file watching (via `files.watcherExclude` in Machine settings):

- `**/node_modules/**`
- `**/.git/objects/**`, `**/.git/subtree-cache/**`
- `**/venv/**`
- `**/__pycache__/**`
- `**/.claude/**`
- `**/tmp/**`, `**/cache/**`
- `**/.openvscode-server/**`

Agent context files (CLAUDE.md, AGENTS.md, GEMINI.md) are hidden from the explorer via `files.exclude`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SESSION_TYPE` | — | `auth_setup` or `agent_session` |
| `AGENT_NAME` | Agent | Display name in terminal |
| `TTYD_CMD` | bash | CLI command for terminal |
| `AGENT_PROMPT` | — | Non-interactive prompt text |
| `VSCODE_TOKEN` | — | Connection token for IDE auth |
| `ROUTE_TOKEN` | — | Traefik route token for URL paths |
| `WORKSPACE` | /workspace | Working directory |
| `REPO_URL` | — | Git repo to clone at start |
| `REPO_BRANCH` | — | Branch to clone |

## OpenVSCode Server CLI Options

Full reference from [serverEnvironmentService.ts](https://github.com/gitpod-io/openvscode-server/blob/main/src/vs/server/node/serverEnvironmentService.ts) (v1.106.x).

### Server Setup

| Option | Description |
|--------|-------------|
| `--host <ip>` | Host/IP to listen on. Default: `localhost` |
| `--port <port\|range>` | Port or range (e.g. `8000-9000`). `0` = random free port |
| `--socket-path <path>` | Unix socket path (alternative to host/port) |
| `--server-base-path <path>` | URL base path for web UI and API. Default: `/` |
| `--connection-token <token>` | Secret token required with all requests |
| `--connection-token-file <path>` | Path to file containing connection token |
| `--without-connection-token` | Run without auth token (use only behind reverse proxy) |
| `--accept-server-license-terms` | Accept license without prompt |
| `--server-data-dir <path>` | Directory for server data (settings, state, extensions) |
| `--telemetry-level <level>` | `off`, `crash`, `error`, `all`. Overridden by client on connect |
| `--disable-websocket-compression` | Disable WebSocket compression |
| `--print-startup-performance` | Print startup timing metrics |
| `--print-ip-address` | Print resolved IP address |

### VS Code Options

| Option | Description |
|--------|-------------|
| `--user-data-dir <path>` | Custom user data directory |
| `--disable-telemetry` | Disable all telemetry |
| `--disable-workspace-trust` | Skip workspace trust prompts |
| `--disable-experiments` | Disable A/B experiment features |
| `--file-watcher-polling` | Use polling instead of inotify for file watching |
| `--log <level>` | `trace`, `debug`, `info`, `warn`, `error`, `critical`, `off` |
| `--force-disable-user-env` | Do not resolve shell environment |
| `--enable-proposed-api <ext,...>` | Enable proposed API for listed extension IDs |

### Web UI Options

| Option | Description |
|--------|-------------|
| `--default-folder <path>` | Folder to open when no path in browser URL |
| `--default-workspace <path>` | Workspace file to open when no path in browser URL |
| `--enable-sync` | Enable Settings Sync |
| `--github-auth <token>` | GitHub auth token for built-in GitHub features |

### Extension Management

| Option | Description |
|--------|-------------|
| `--extensions-dir <path>` | Custom extensions directory |
| `--install-extension <id\|vsix>` | Install extension by ID or VSIX path |
| `--install-builtin-extension <id>` | Install built-in extension |
| `--uninstall-extension <id>` | Uninstall extension by ID |
| `--update-extensions` | Update all installed extensions |
| `--list-extensions` | List installed extensions |
| `--show-versions` | Show extension versions with `--list-extensions` |
| `--force` | Force install (skip compat checks) |
| `--pre-release` | Install pre-release version |
| `--start-server` | Start server after install/uninstall operations |

### Remote Development

| Option | Description |
|--------|-------------|
| `--enable-remote-auto-shutdown` | Auto-shutdown when no clients connected |
| `--remote-auto-shutdown-without-delay` | Shutdown immediately (no grace period) |
| `--reconnection-grace-time <seconds>` | Grace time for client reconnection. Default: `10800` (3h) |
| `--use-host-proxy` | Use host system proxy settings |
| `--without-browser-env-var` | Don't set `BROWSER` env var |

### Our Configuration

Flags used in `entrypoint.sh`:

```
--host 0.0.0.0
--port 8443
--default-folder /workspace
--disable-telemetry
--file-watcher-polling
--connection-token-file /tmp/.vscode-connection-token
--server-base-path /t/{route_token}/ide
```

### Notes on View State

View visibility (Outline, Timeline panels) is stored in the **browser's IndexedDB**, not on the server. `timeline.enabled: false` in Machine settings works server-side, but Outline can only be hidden via UI (right-click header → Hide) — persists per browser origin.

## Building

```bash
docker build -t palad-base:latest docker/base/
```
