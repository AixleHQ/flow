# Epic 35: BMAD Method — Container Hardening & Resilience

> BMAD integration works reliably across all 4 agent runtimes, installation does not block session on failures, and Node.js is guaranteed available in containers. Installation runs in parallel with other session setup steps.

**Phase:** 19 (Depends on: Epic 33, 17)

**NFRs covered:** NFR1, NFR2, NFR3, NFR4, NFR7

---

## Story 35.1: Docker — Node.js v20+ in Agent Container Images

As a **platform operator**,
I want Node.js v20+ pre-installed in all agent container images,
So that `npx bmad-method install` can execute without additional runtime setup.

**Acceptance Criteria:**

**Given** the base agent container image is built
**When** `node --version` is run inside the container
**Then** it returns v20.x or higher

**Given** the base agent container image is built
**When** `npx --version` is run inside the container
**Then** it returns a valid npm/npx version

**Given** all 4 agent runtime images (cursor_cli, claude_code, codex, gemini_cli)
**When** each image is inspected
**Then** all contain Node.js v20+

**Implementation Notes:**
- Check current Dockerfiles for existing Node.js presence
- If missing: add `RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs` (or equivalent for the base OS)
- Add to base image so all derived images inherit it
- Verify with CI build test

---

## Story 35.2: Graceful Error Handling in BmadMethodInjector

As a **developer enabling BMAD**,
I want the session to start normally even if BMAD installation fails,
So that a BMAD failure never blocks my work.

**Acceptance Criteria:**

**Given** BMAD installation (`npx bmad-method install`) fails with a non-zero exit code
**When** the session context assembly continues
**Then** the error is logged with full command output at `warn` level
**And** the session proceeds without BMAD
**And** the `ContextBuilders::BmadMethod` builder does NOT generate a context section (since BMAD files are absent)

**Given** BMAD installation times out (exceeds 60 seconds)
**When** the timeout is reached
**Then** the process is killed
**And** the error is logged
**And** the session proceeds without BMAD

**Given** `npx` is not available in the container (Node.js missing)
**When** BmadMethodInjector attempts to run the install
**Then** the error is caught and logged
**And** the session proceeds without BMAD

**Given** a BMAD installation failure occurs
**When** the session's context_metadata is stored
**Then** it includes `bmad_install_status: "failed"` and `bmad_install_error: "<message>"` for traceability

**Implementation Notes:**
- Wrap `run_bmad_install` in `begin/rescue` with `RuntimeError` and timeout handling
- Log to `Rails.logger.warn` with structured message
- Store install status in session context metadata for debugging
- 60-second timeout via `Timeout.timeout(60)` or runtime-level timeout

---

## Story 35.3: Parallel BMAD Installation

As a **developer**,
I want BMAD installation to run in parallel with other session setup steps,
So that it does not add 10-30 seconds to my session startup time.

**Acceptance Criteria:**

**Given** a session with `bmad_enabled: true`
**When** `assemble_session_context` runs
**Then** `BmadMethodInjector#inject!` executes concurrently with other independent steps (e.g., context file generation can proceed while BMAD installs)

**Given** BMAD installation takes 15 seconds and other steps take 10 seconds
**When** both run in parallel
**Then** total time is approximately 15 seconds (not 25)

**Given** BMAD installation runs in parallel
**When** it completes (success or failure)
**Then** the result is awaited before the final context file is written (since ContextBuilders::BmadMethod needs to check if BMAD files exist)

**Implementation Notes:**
- Run BmadMethodInjector in a Thread/Future within `assemble_session_context`
- Await the result before `inject_context_file` step (the builder needs to know if BMAD is present)
- Use `Concurrent::Promises.future` or simple `Thread.new` with join
- Measure and log the parallel execution timing

---

## Story 35.4: E2E Testing — BMAD on All Agent Runtimes

As a **platform team**,
I want end-to-end tests verifying BMAD integration across all 4 agent runtimes,
So that we have confidence BMAD works correctly regardless of the agent type.

**Acceptance Criteria:**

**Given** a test session with `bmad_enabled: true` and agent_type `cursor_cli`
**When** the session completes context assembly
**Then** BMAD files exist at `/workspace/_bmad/`
**And** skills exist at `/workspace/.cursor/skills/`
**And** the context file contains a `<bmad-method>` section
**And** `/workspace/_bmad/core/config.yaml` contains the configured user name and language

**Given** a test session with agent_type `claude_code`
**When** the session completes context assembly
**Then** skills exist at `/workspace/.claude/skills/`
**And** `--tools claude-code` was used in the install command

**Given** a test session with agent_type `codex`
**When** the session completes context assembly
**Then** skills exist at `/workspace/.agents/skills/`

**Given** a test session with agent_type `gemini_cli`
**When** the session completes context assembly
**Then** skills exist at `/workspace/.gemini/skills/`

**Given** any agent runtime with BMAD enabled
**When** VS Code settings are checked
**Then** `files.exclude` contains all BMAD hidden paths

**Implementation Notes:**
- Integration/system tests using real container execution (or mocked runtime)
- Test the full pipeline: session create → assemble context → verify filesystem
- Verify agent_type → tools flag mapping produces correct skill directories
- Can be run as part of CI with container-based test infrastructure
