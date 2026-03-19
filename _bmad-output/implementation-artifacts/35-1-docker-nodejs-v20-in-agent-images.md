# Story 35.1: Docker — Node.js v20+ in Agent Container Images

Status: ready-for-dev

## Story

As a **platform operator**,
I want Node.js v20+ pre-installed in all agent container images,
so that `npx bmad-method install` can execute without additional runtime setup.

## Acceptance Criteria

1. **Given** the base agent container image is built
   **When** `node --version` is run inside the container
   **Then** it returns v20.x or higher

2. **Given** the base agent container image is built
   **When** `npx --version` is run inside the container
   **Then** it returns a valid npm/npx version

3. **Given** all 4 agent runtime images (cursor_cli, claude_code, codex, gemini_cli)
   **When** each image is inspected
   **Then** all contain Node.js v20+

4. **Given** the base image is used for building agent images
   **When** a derived image is built
   **Then** it inherits Node.js without additional installation steps

## Tasks / Subtasks

- [ ] Task 1: Verify current state (AC: #1–#4)
  - [ ] Confirm `docker/base/Dockerfile` uses `FROM node:22-slim` as base
  - [ ] Run `node --version` and `npx --version` in a built base image container
  - [ ] Verify all 4 agent Dockerfiles inherit from base image
- [ ] Task 2: Add CI verification (AC: #1–#3)
  - [ ] Add a test step in CI that runs `node --version` inside each built agent image
  - [ ] Assert version >= 20
  - [ ] Add `npx --version` check as well
- [ ] Task 3: Document Node.js availability (AC: #4)
  - [ ] Add a comment in `docker/base/Dockerfile` noting that Node.js is required for BMAD
  - [ ] Update any container documentation if exists

## Dev Notes

- **Current state: ALREADY SATISFIED.** The base image `docker/base/Dockerfile` line 16 uses `FROM node:22-slim`, which provides Node.js v22 (exceeds v20+ requirement).
- All 4 agent images inherit from this base:
  - `docker/cursor-cli/Dockerfile` — `FROM ${BASE_IMAGE}`
  - `docker/claude-code/Dockerfile` — `FROM ${BASE_IMAGE}`
  - `docker/codex/Dockerfile` — `FROM ${BASE_IMAGE}`
  - `docker/gemini-cli/Dockerfile` — `FROM ${BASE_IMAGE}`
- **This story is primarily a verification/documentation story.** No Dockerfile changes needed.
- The main deliverable is the CI test asserting Node.js availability, which prevents future regressions if the base image changes.

### Key Evidence

```dockerfile
# docker/base/Dockerfile line 16
FROM node:22-slim
```

Existing npm usage in base:
- `npm install -g @playwright/mcp` (line 94)
- `npx playwright install --with-deps chromium` (line 96)

### References

- [Source: docker/base/Dockerfile#L16] — base image with Node 22
- [Source: docker/codex/Dockerfile] — inherits from base
- [Source: docker/claude-code/Dockerfile] — inherits from base
- [Source: docker/cursor-cli/Dockerfile] — inherits from base
- [Source: docker/gemini-cli/Dockerfile] — inherits from base
- [Source: ai/epics/epic-35-bmad-container-hardening.md#Story-35.1] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
