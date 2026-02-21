# Story 15.1: Install OpenVSCode Server in Base Docker Image

Status: review

## Story

As a platform engineer,
I want OpenVSCode Server installed in the agent container base image,
so that it's available as a service alongside ttyd for full IDE editing experience.

## Acceptance Criteria

1. **AC1: Binary installation** — OpenVSCode Server v1.106.3 (stable) is downloaded and extracted to `/opt/openvscode-server/` in `docker/base/Dockerfile`. Both amd64 and arm64 architectures are supported via `dpkg --print-architecture` (same pattern as ttyd installation on line 49-52).

2. **AC2: Entrypoint integration** — `docker/base/entrypoint.sh` starts OpenVSCode Server in background with flags: `--host 0.0.0.0 --port 8443 --without-connection-token --default-folder /workspace --disable-telemetry`. Health check confirms process is running (same `kill -0` pattern as watcher/ttyd).

3. **AC3: Port exposure** — `EXPOSE 8443` added to Dockerfile alongside existing 7681 and 4040.

4. **AC4: File permissions** — `/opt/openvscode-server/` is owned by root but world-readable+executable, so non-root agent users (e.g. `claude` uid 1001 in claude-code image) can run the server binary.

5. **AC5: Cleanup in shutdown** — `cleanup()` function in entrypoint.sh kills the OpenVSCode Server PID on SIGTERM/SIGINT. `wait -n` includes the new PID.

6. **AC6: Smoke test** — Container starts successfully, `curl http://localhost:8443` returns HTTP 200, and ttyd on 7681 + watcher on 4040 continue to work.

## Tasks / Subtasks

- [x] Task 1: Add OpenVSCode Server installation to Dockerfile (AC: #1, #3, #4)
  - [x] 1.1 Add download+extract block after ttyd section using multi-arch pattern
  - [x] 1.2 Add `EXPOSE 8443` to ports comment and EXPOSE directive
  - [x] 1.3 Ensure `/opt/openvscode-server/` has correct permissions (755)
- [x] Task 2: Update entrypoint.sh to start OpenVSCode Server (AC: #2, #5)
  - [x] 2.1 Add OpenVSCode Server startup section after watcher block
  - [x] 2.2 Add health check with `kill -0` and status log message
  - [x] 2.3 Add `OPENVSCODE_PID` to cleanup function
  - [x] 2.4 Add PID to `wait -n` call
- [x] Task 3: Verify all services start correctly (AC: #6)
  - [x] 3.1 Build image locally: `docker build -t palad/agent-base:test -f docker/base/Dockerfile docker/base/`
  - [x] 3.2 Run container and verify all 3 ports respond (7681, 4040, 8443)
  - [x] 3.3 Verify non-root user can access (test with claude-code image)

## Dev Notes

### Docker Image Architecture

The image chain is: `node:22-slim` → `palad/agent-base:latest` (this Dockerfile) → per-agent images. All agent images inherit from base, so installing here makes OpenVSCode Server available everywhere.

Per-agent images create non-root users and may change `USER`:
- `docker/claude-code/Dockerfile` — user `claude` (line 15: `useradd -m -d /home/claude`)
- Other agents follow similar patterns

The `/opt/openvscode-server/` dir must stay root-owned but world-readable so any user can execute the binary. The server creates its user-data dir at runtime under `~/.openvscode-server/` (in the active user's home).

### Exact Installation Block

Follow the ttyd pattern. Release URL format:

```
https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.106.3/openvscode-server-v1.106.3-linux-{x64|arm64}.tar.gz
```

Architecture mapping: `amd64` → `x64`, `arm64` → `arm64`.

Dockerfile block (insert after ttyd section, before watcher section):

```dockerfile
# -----------------------------------------------------------------------------
# Install OpenVSCode Server from GitHub releases
# -----------------------------------------------------------------------------
ARG OPENVSCODE_VERSION=1.106.3
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then OVS_ARCH="x64"; else OVS_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${OPENVSCODE_VERSION}/openvscode-server-v${OPENVSCODE_VERSION}-linux-${OVS_ARCH}.tar.gz" | \
    tar -xz -C /opt/ && \
    mv /opt/openvscode-server-v${OPENVSCODE_VERSION}-linux-${OVS_ARCH} /opt/openvscode-server && \
    chmod -R 755 /opt/openvscode-server
```

### Exact Entrypoint Block

Insert after the watcher section (after line 77 of current entrypoint.sh), before the ttyd section:

```bash
# -----------------------------------------------------------------------------
# Start OpenVSCode Server (IDE)
# -----------------------------------------------------------------------------
OPENVSCODE_PORT="${OPENVSCODE_PORT:-8443}"
/opt/openvscode-server/bin/openvscode-server \
    --host 0.0.0.0 \
    --port "$OPENVSCODE_PORT" \
    --without-connection-token \
    --default-folder "$WORKSPACE" \
    --disable-telemetry \
    > /dev/null 2>&1 &
OPENVSCODE_PID=$!

sleep 1
if kill -0 $OPENVSCODE_PID 2>/dev/null; then
    echo -e "${GREEN}✅ OpenVSCode Server ready (port $OPENVSCODE_PORT)${NC}"
else
    echo -e "${YELLOW}⚠️  OpenVSCode Server failed to start${NC}"
fi
```

Update cleanup function:

```bash
cleanup() {
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $MITM_PID 2>/dev/null || true
    kill $WATCHER_PID 2>/dev/null || true
    kill $OPENVSCODE_PID 2>/dev/null || true
    kill $TTYD_PID 2>/dev/null || true
    exit 0
}
```

Update wait-n:

```bash
wait -n $WATCHER_PID $OPENVSCODE_PID $TTYD_PID 2>/dev/null || true
```

### Port Map (after this story)

| Port | Service | Status |
|------|---------|--------|
| 7681 | ttyd (web terminal) | existing |
| 4040 | file watcher (HTTP + WS) | existing (removed in Story 15.7) |
| 8443 | OpenVSCode Server (IDE) | **new** |
| 8888 | MITM proxy (internal) | existing |

### EXPOSE Directive Update

```dockerfile
# Ports:
#   7681 - ttyd web terminal
#   4040 - file watcher WebSocket + HTTP API
#   8443 - OpenVSCode Server (IDE)
#   8888 - MITM proxy (internal)
EXPOSE 7681 4040 8443
```

### Image Size Consideration

OpenVSCode Server tarball is ~90MB compressed, ~300MB extracted. This increases base image size from ~1.2GB to ~1.5GB. Acceptable for IDE-class functionality. No optimization needed now — all agent images already exceed 1GB due to CLI tools.

### Key Flags Reference

| Flag | Purpose |
|------|---------|
| `--host 0.0.0.0` | Listen on all interfaces (required for Docker) |
| `--port 8443` | Custom port (avoid conflict with default 3000) |
| `--without-connection-token` | No auth initially (Story 15.4 adds token) |
| `--default-folder /workspace` | Open workspace directory on start |
| `--disable-telemetry` | No telemetry in container environment |

Future flags (added in later stories):
- `--connection-token-file` (Story 15.4)
- `--server-base-path` (Story 15.2)
- `--file-watcher-polling` (Story 15.8)

### What NOT To Change

- Do NOT modify per-agent Dockerfiles (claude-code, cursor-cli, codex, gemini-cli) — they inherit from base
- Do NOT modify Traefik labels or container strategies — that's Story 15.2/15.3
- Do NOT remove the watcher — it stays until Story 15.7
- Do NOT add connection token logic — that's Story 15.4

### Project Structure Notes

- `docker/base/Dockerfile` — main file to edit
- `docker/base/entrypoint.sh` — second file to edit
- `docker/base/watcher/` — untouched in this story
- `docker/claude-code/Dockerfile` — verify compatibility, no changes needed

### References

- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.1]
- [Source: ai/vscode-server-and-monaco-editor.md#Executive summary]
- [Source: docker/base/Dockerfile — ttyd installation pattern lines 49-52]
- [Source: docker/base/entrypoint.sh — service startup pattern lines 66-77]
- [Source: docker/claude-code/Dockerfile — non-root user pattern lines 15-26]
- [OpenVSCode Server releases: https://github.com/gitpod-io/openvscode-server/releases]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus (via Cursor)

### Debug Log References

### Completion Notes List

- Installed OpenVSCode Server v1.106.3 in base Docker image via multi-arch tarball download (same pattern as ttyd)
- Added startup block in entrypoint.sh between watcher and ttyd sections with health check
- Added OPENVSCODE_PID to cleanup() and wait-n for graceful shutdown
- Smoke test passed: all 3 ports (7681 ttyd, 4040 watcher, 8443 OpenVSCode) respond HTTP 200
- Build time: ~150s (tarball download + extraction is the bottleneck)
- No changes to per-agent Dockerfiles needed — they inherit from base

### Change Log

- 2026-02-20: Implemented Story 15.1 — OpenVSCode Server installation in base image

### File List

- `docker/base/Dockerfile` — added OpenVSCode Server download+extract block, updated EXPOSE and header comment
- `docker/base/entrypoint.sh` — added OpenVSCode Server startup section, updated cleanup() and wait-n
