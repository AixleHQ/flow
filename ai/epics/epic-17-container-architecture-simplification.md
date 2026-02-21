# Epic 17: Container Architecture Simplification

> Simplify the container execution pipeline by splitting workflows, eliminating strategy indirection in activities, and optimizing Docker builds for faster iteration.

**Phase:** 10 (Depends on: Epic 8 Unified Container Execution, Epic 10 Sessions Core, Epic 16 Config Normalization)

**User Outcome:** Faster Docker image rebuilds when modifying agent scripts (~5s instead of ~5min). More reliable session state tracking — sessions show as "running" immediately when the container is ready, and correctly transition to "failed" on errors. Cleaner codebase with ~40% less code in the workflow/activity layer.

---

## Part A: Docker Build Optimization

### Story 17.1: Two-Tier Base Image

**As a** developer,
**I want** script changes to not trigger full agent image rebuilds,
**so that** iterating on entrypoint/watcher/logger is fast (~5s instead of ~5min).

**Acceptance Criteria:**

1. **Dockerfile.core** — New `docker/base/Dockerfile.core` with only heavy, rarely-changing layers: `node:22-slim`, apt-get system deps, mitmproxy, ttyd, OpenVSCode Server, workspace dirs. No scripts (entrypoint, watcher, auth-check, logger).
2. **Agent Dockerfiles** — Each agent Dockerfile (`codex`, `claude-code`, `cursor-cli`, `gemini-cli`) restructured:
   - `FROM palad/agent-base-core:latest`
   - Agent CLI installation (npm install / curl install) — **cached when only scripts change**
   - Shared scripts block at the end: tmux config, inputrc, vscode-settings, watcher (package.json + npm install + index.js), auth-check, logger, entrypoint
   - Scripts ordered by stability (most stable first, entrypoint last)
3. **Build context** — All agents use `docker/` as build context, with `COPY base/...` paths.
4. **Makefile** — `build-agents` target: build core first, then 4 agents in parallel (`&` + `wait`).
5. **docker-compose.yml** — `agent-base` service replaced with `agent-base-core` pointing to `Dockerfile.core`. Agent services use `context: ./docker` with `dockerfile: <agent>/Dockerfile`.
6. **Verification** — Changing `entrypoint.sh` and rebuilding all agents takes <10s (agent install layers cached).

**Dev Notes:**
- Old `docker/base/Dockerfile` can be kept as convenience "full base" for testing, or removed
- Docker layer caching: layers are validated top-to-bottom; once a layer invalidates, all below re-run. Putting agent installs before scripts ensures installs stay cached.

---

## Part B: Workflow Split & Simplification

### Story 17.2: AgentContainerWorkflow

**As a** platform engineer,
**I want** agent container lifecycle managed by a dedicated workflow that takes only `session_id`,
**so that** activities don't manually resolve strategies and the code is minimal.

**Acceptance Criteria:**

1. **Workflow** — New `Workflows::AgentContainerWorkflow` with input `{ session_id: }`:
   - Step 1: `PullAgentImageActivity(session_id)` — session resolves image via strategy
   - Step 2: `ExecuteAgentContainerActivity(session_id)` — `ContainerService.execute(session)` (strategy resolved inside)
   - Step 3: Wait for `container_finished` signal (if interactive) or skip (if non-interactive, exec already blocked)
   - Step 4: `CleanupAgentContainerActivity(session_id)` — cleanup via strategy
2. **Signal logic** — Workflow checks `session.mode` or uses `agent_completed` flag from execute result (same as current).
3. **Timeout** — `AGENT_SIGNAL_TIMEOUT = 82_800` (23h). Execute timeout: 300s for interactive (quick phases), `AGENT_SIGNAL_TIMEOUT + 3000` for non-interactive.
4. **Error handling** — If any activity fails, workflow proceeds to cleanup (best-effort). Session is already marked failed by the activity.
5. **Registration** — Register in `WorkflowService` / `schedules.yml`.

**Dev Notes:**
- No `strategy_type`, no `strategy_input` hash. Just `session_id`.
- Workflow doesn't know about strategy internals — it's a thin orchestrator.

---

### Story 17.3: ToolExecutionWorkflow

**As a** platform engineer,
**I want** tool execution managed by a separate, simpler workflow,
**so that** tool-specific logic isn't tangled with agent session state.

**Acceptance Criteria:**

1. **Workflow** — New `Workflows::ToolExecutionWorkflow` with input `{ tool_id:, parameters:, project_id:, timeout: }`:
   - Step 1: `PullToolImageActivity(tool_id)` — resolves image from `tool.docker_image`
   - Step 2: `ExecuteToolContainerActivity(tool_id:, parameters:, project_id:, timeout:)` — builds `ToolExecutionStrategy`, runs `ContainerService.execute`
   - Step 3: `CleanupToolContainerActivity(container_id:, tool_id:)` — stop + remove container
2. **No signal wait** — Tool containers run to completion in the execute phase.
3. **No session state** — No `mark_session_running`, no `mark_session_failed`. Errors propagate as activity failures.
4. **Timeout** — `min(timeout, 1800) + 300` overhead for phases.
5. **Registration** — Register in `WorkflowService`.

**Dev Notes:**
- Tools are fire-and-forget from the workflow perspective — simpler than agents.
- `ContainerWorkflowService.execute_tool` and `start_tool_execution` updated to use new workflow.

---

### Story 17.4: Strategy Resolution from Session

**As a** platform engineer,
**I want** `TerminalSession` to know how to build its own strategy,
**so that** activities and services don't manually resolve strategy types.

**Acceptance Criteria:**

1. **TerminalSession#strategy** — New method:
   ```ruby
   def strategy
     case session_type
     when "auth_setup"
       ContainerStrategies::AgentAuthStrategy.new(strategy_params)
     when "agent_session"
       ContainerStrategies::AgentSessionStrategy.new(strategy_params)
     else
       raise "No strategy for session_type: #{session_type}"
     end
   end
   ```
2. **strategy_params** — Private method returning hash with `user_id`, `agent_type`, `session_id`, `route_token`, `credential` (resolved from user's agent_credentials).
3. **ContainerService.execute** — New signature: `ContainerService.execute(session:)`. Internally calls `session.strategy`, runs lifecycle phases.
4. **ContainerService.cleanup** — New signature: `ContainerService.cleanup(session:)`. Resolves strategy, runs `before_cleanup` + `cleanup`.
5. **Backward compat** — Keep `execute(strategy:, input:)` signature during migration, deprecate.

**Dev Notes:**
- This eliminates `STRATEGY_MAP`, `build_strategy_from_input`, `build_strategy_from_session`, `prepare_strategy_input` from `ContainerActivityBase` — ~50 lines of routing code.
- `ToolExecutionStrategy` is NOT resolved from session — tools build their strategy directly in the tool activity.

---

### Story 17.5: Thin Agent Activities

**As a** platform engineer,
**I want** agent activities to be <10 lines each,
**so that** all logic lives in strategies and services, not in Temporal activity code.

**Acceptance Criteria:**

1. **PullAgentImageActivity** — `session.strategy.pull_image`. 
2. **ExecuteAgentContainerActivity** — `ContainerService.execute(session: session)`.
3. **CleanupAgentContainerActivity** — `ContainerService.cleanup(session: session)`.
4. **Error handling** — Unified rescue in a shared base class: log, wrap with `TemporalExceptions`, re-raise. `mark_session_failed` called by strategy's error handling, not by activity.
5. **Remove** — `ContainerActivityBase#prepare_strategy_input`, `build_strategy_from_input`, `build_strategy_from_session`, `STRATEGY_MAP`. These become dead code after Stories 17.2–17.4.

**Dev Notes:**
- Activities become pure Temporal plumbing — find session, delegate to service, handle Temporal error wrapping.

---

### Story 17.6: Update ContainerWorkflowService

**As a** platform engineer,
**I want** `ContainerWorkflowService` simplified to match new workflows,
**so that** the entry point for starting workflows is clean.

**Acceptance Criteria:**

1. **Agent methods** — `start_agent_auth(session:)` and `start_agent_session(session:, credential:)` → both call `start_agent_workflow(session:)` which sends `{ session_id: session.id }` to `AgentContainerWorkflow`.
2. **Tool methods** — `start_tool_execution` and `execute_tool` → send `{ tool_id:, parameters:, project_id:, timeout: }` to `ToolExecutionWorkflow`.
3. **Remove** — `resolve_agent_image` (now in strategy), `strategy_input` hash building (now in session.strategy_params).
4. **State machine** — `start_temporal_workflow` callback updated to call simplified `ContainerWorkflowService.start_agent_workflow(session: self)`.

---

### Story 17.7: Remove UnifiedContainerWorkflow

**As a** platform engineer,
**I want** the old unified workflow removed,
**so that** there's no dead code or confusion about which workflow to use.

**Acceptance Criteria:**

1. **Delete** — `Workflows::UnifiedContainerWorkflow`, old activity files (`ExecuteContainerActivity`, `PullDockerImageActivity`, `CleanupContainerActivity` — if replaced by new ones).
2. **Delete** — Old `ContainerActivityBase` methods that are no longer used.
3. **Update** — Temporal worker registration to use new workflow classes.
4. **Update** — Any tests referencing old workflow.
5. **Verify** — No references to `UnifiedContainerWorkflow` remain in codebase.

---

## Part C: Session Lifecycle Improvements

### Story 17.8: Strategy-Driven Session State Updates

**As a** platform engineer,
**I want** session state transitions managed by strategies (not activities),
**so that** the session is marked "running" at the right moment and "failed" on errors.

**Acceptance Criteria:**

1. **mark_session_running in exec** — `AgentAuthStrategy#exec` calls `mark_session_running` at the beginning, after container is started + ports healthy + credentials loaded. Inherited by `AgentSessionStrategy` via `super`.
2. **mark_session_failed on error** — When `ContainerService` catches a phase error and the strategy has a `session_id`, it marks the session as failed before re-raising.
3. **Conditional port checks** — `AgentSessionStrategy#services_ports` returns `[7681]` for non-interactive sessions (no OpenVSCode Server), `[7681, 8443]` for interactive.
4. **No activity involvement** — Activities don't call `mark_session_running` or `mark_session_failed`. All session state transitions happen in strategies or services.

**Dev Notes:**
- This is partially implemented already (current sprint). Story captures the final desired state.
- `mark_session_running` is a private method on `AgentAuthStrategy`.
- `mark_session_failed` can live on `BaseStrategy` or in `ContainerService`'s error handler.

---

## Dependencies

```
17.1 (Docker build optimization) — independent, can ship first

17.4 (Strategy from session)
  └── 17.2 (AgentContainerWorkflow)
        └── 17.5 (Thin agent activities)
              └── 17.6 (Update ContainerWorkflowService)
                    └── 17.7 (Remove old unified workflow)

17.3 (ToolExecutionWorkflow) — parallel with 17.2, no session dependency

17.8 (Session state in strategies) — partially done, finalize after 17.4
```

Stories 17.1 and 17.3 can be developed independently.
Stories 17.2 and 17.3 can be developed in parallel.
Story 17.7 is the final cleanup after all migrations are complete.
