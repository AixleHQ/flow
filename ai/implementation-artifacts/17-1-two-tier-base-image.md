# Story 17.1: Two-Tier Base Docker Image

Status: done

## Story

As a developer,
I want script changes (entrypoint, watcher, logger) to not trigger full agent image rebuilds,
so that iterating on container runtime logic is fast (~5s instead of ~5min).

## Acceptance Criteria

1. **AC1: Dockerfile.core** — New `docker/base/Dockerfile.core` contains only heavy, rarely-changing layers: `node:22-slim`, apt-get system deps (bash, git, ripgrep, fd-find, jq, curl, tree, tmux, tini, python3, make, g++), mitmproxy 10.2.4, ttyd 1.7.7, OpenVSCode Server 1.106.3, workspace dirs. No scripts (entrypoint, watcher, auth-check, logger, inputrc, vscode-settings, tmux config).

2. **AC2: Agent Dockerfiles restructured** — Each of the 4 agent Dockerfiles (`codex`, `claude-code`, `cursor-cli`, `gemini-cli`) follows pattern: `FROM palad/agent-base-core:latest` → agent CLI installation → shared scripts block (tmux config, inputrc, vscode-settings, watcher package.json+install+index.js, auth-check, logger, entrypoint). Agent install layers are cached when only scripts change.

3. **AC3: Build context** — All agents use `docker/` as build context with `COPY base/...` paths for shared scripts.

4. **AC4: Parallel builds** — Makefile `build-agents` target builds core first, then 4 agents in parallel (`&` + `wait`).

5. **AC5: docker-compose.yml** — `agent-base` service replaced with `agent-base-core` pointing to `Dockerfile.core`. Agent services use `context: ./docker` with per-agent Dockerfile paths.

6. **AC6: Cache verification** — Changing `entrypoint.sh` and running `make build-agents` completes in <10s with all agent install layers cached.

## Tasks / Subtasks

- [x] Task 1: Create `docker/base/Dockerfile.core` (AC: #1)
- [x] Task 2: Restructure `docker/codex/Dockerfile` (AC: #2, #3)
- [x] Task 3: Restructure `docker/claude-code/Dockerfile` (AC: #2, #3)
- [x] Task 4: Restructure `docker/cursor-cli/Dockerfile` (AC: #2, #3)
- [x] Task 5: Restructure `docker/gemini-cli/Dockerfile` (AC: #2, #3)
- [x] Task 6: Update Makefile `build-agents` target (AC: #4)
- [x] Task 7: Update `docker-compose.yml` (AC: #5)
- [x] Task 8: Verify cache behavior (AC: #6)

## Dev Notes

- Scripts ordered by stability in each agent Dockerfile: tmux config (very stable) → inputrc → vscode-settings → watcher deps → watcher source → auth-check → logger → entrypoint (changes most often). This maximizes cache hits.
- Docker layer caching: layers validated top-to-bottom. Once a layer invalidates, all below re-run. Agent installs placed before scripts ensures installs stay cached.
- Old `docker/base/Dockerfile` kept as convenience for testing full base image.

### References

- [Source: docker/base/Dockerfile.core](docker/base/Dockerfile.core)
- [Source: docker/codex/Dockerfile](docker/codex/Dockerfile) — template for all agents
- [Source: Makefile](Makefile) — build-agents target

## Completion Notes

Implemented and verified. Entrypoint-only change rebuilds all 4 agents in ~5s (previously ~5min). All agent CLI install layers remain cached.
