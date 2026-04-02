# Story 2.3: Configure Claude Code Agent

Status: done

## Story

As a user,
I want to authenticate and configure my Claude Code agent,
So that I can use it in future sessions.

## Acceptance Criteria

1. **Given** I have selected Claude Code in the agent selection step (Step 2)
   **When** I reach Step 3 "Authenticate" and click on Claude Code agent
   **Then** I see instructions for configuring Claude Code
   **And** I see a "Start Authentication" button
   **And** the agent card shows status: "Not Started"

2. **Given** I am on the Claude Code authentication screen
   **When** I click "Start Authentication"
   **Then** a `TerminalSession` is created with type: `auth_setup` and agent: `claude_code`
   **And** the session state machine starts in `not_started` state
   **And** a Temporal workflow is triggered: `AgentAuthWorkflow`
   **And** the session transitions to `started` state
   **And** I see a loading indicator: "Starting terminal session..."

3. **Given** the Temporal workflow has started
   **When** the first activity `StartAuthTerminalActivity` executes
   **Then** a Docker container is started via `ContainerService` with:
   - Agent CLI installed (Claude Code)
   - ttyd web terminal configured
   - WebSocket endpoint exposed
   **And** the activity returns WebSocket URL for terminal connection
   **And** I see the terminal embedded in UI via WebSocket connection
   **And** the session transitions to `running` state

4. **Given** I am connected to the authentication terminal
   **When** the terminal loads
   **Then** I can interact with the terminal to run authentication commands:
   - `claude login` (or similar)
   - Configure theme (dark/light)
   - Configure other preferences
   **And** the terminal is isolated to my user session
   **And** I can see terminal output in real-time via WebSocket

5. **Given** I have completed authentication in the terminal
   **When** authentication is successful (token saved in container's home directory, e.g., `~/.claude/config`)
   **Then** I see a "Finish Authentication" button in the UI
   **And** I can click "Finish Authentication" to mark completion
   **And** the session transitions to `finished` state

6. **Given** I clicked "Finish Authentication"
   **When** the session state changes to `finished`
   **Then** Temporal workflow continues with `CollectArtifactsActivity`
   **And** the activity extracts authentication artifacts from container:
   - Config files (e.g., `~/.claude/config`)
   - API tokens
   - Preferences
   **And** the session transitions to `collected` state
   **And** artifacts are saved to `AgentCredential` model (or user's encrypted storage)
   **And** the agent type is added to user's `configured_agents` array
   **And** the container is stopped and removed
   **And** I see a success indicator (checkmark) on the Claude Code card

7. **Given** I am on Step 3 "Authenticate"
   **When** I have finished authentication for at least one agent (session state: `collected`)
   **Then** the "Continue" button becomes enabled
   **And** I can proceed to Step 4 "Complete"
   **And** I can skip authenticating other selected agents (they remain in "not_started" state)
   **And** only successfully authenticated agents (state: `collected`) are added to `configured_agents`

8. **Given** I have authenticated Claude Code
   **When** I return to edit mode (`/onboarding` after completing onboarding)
   **Then** I see Claude Code marked as "Authenticated" with status: `collected`
   **And** I can re-authenticate if needed (creates new `TerminalSession`)
   **And** I can authenticate additional agents that were previously skipped

9. **Given** I start authenticating Claude Code but encounter an error
   **When** the container fails to start or Temporal activity fails
   **Then** the session transitions to `failed` state
   **And** I see an error message in the UI
   **And** I can retry authentication (creates new session)
   **And** the error is logged in Temporal workflow history

10. **Given** the authentication session is running
    **When** I click "Cancel" or close the page
    **Then** the session transitions to `cancelled` state
    **And** the Temporal workflow is cancelled
    **And** the container is stopped and cleaned up
    **And** I can restart authentication later

## Tasks / Subtasks

### Task 1: Create TerminalSession Model with State Machine (AC: 1, 2, 5, 6, 9, 10) ✅ COMPLETE

- [x] Create migration: `db/migrate/20260124121206_create_terminal_sessions.rb`
- [x] Create model: `app/models/terminal_session.rb` with AASM state machine
- [x] Create factory: `test/factories/terminal_sessions.rb`
- [x] Run migration

**Completed:** Migration created and run. Model includes 7 states (not_started, started, running, finished, collected, failed, cancelled) with proper transitions and callbacks.

### Task 2: Create Temporal Workflow for Agent Authentication (AC: 2, 3, 6) ✅ COMPLETE

- [x] Create workflow: `app/temporal/workflows/agent_auth_workflow.rb` (placeholder)
- [x] Create activity: `app/temporal/activities/start_auth_terminal_activity.rb`
- [x] Create activity: `app/temporal/activities/collect_artifacts_activity.rb`
- [x] Create activity: `app/temporal/activities/stop_container_activity.rb`
- [x] Create service stub: `app/services/temporal_service.rb` (mock for MVP)

**Completed:** All workflow and activity files created. TemporalService provides mock implementation for development (returns mock workflow IDs). Real Temporal integration will be added when Temporal server is configured.

### Task 3: Create ContainerService for Docker Management (AC: 3, 6) ✅ COMPLETE

- [x] Create service: `app/services/container_service.rb` (mock implementation)
  - [x] Method: `start_auth_container(user_id, agent_type)` - Returns mock container_id and websocket_url
  - [x] Method: `start_agent_container(user_id, agent_type, project_id, credentials)` - Stub for Epic 4
  - [x] Method: `extract_files(container_id, paths)` - Returns mock config content
  - [x] Method: `stop_container(container_id)` - Mock cleanup
  - [x] Method: `health_check(container_id, port)` - Mock health check

**Completed:** ContainerService created with mock implementations. Real Docker API integration (via `docker-api` gem) will be added when Docker daemon is accessible from Rails.

### Task 4: Create AgentCredential Model for Storing Auth Artifacts (AC: 6, 8) ✅ COMPLETE

- [x] Create migration: `db/migrate/20260124122449_create_agent_credentials.rb`
- [x] Create model: `app/models/agent_credential.rb` with Rails encryption
- [x] Create factory: `test/factories/agent_credentials.rb`
- [x] Run migration
- [x] Add associations to User model

**Completed:** AgentCredential model created with encrypted storage (`encrypts :encrypted_config_data`). Includes methods: `from_artifacts`, `config_data`, `mount_to_container` (for Epic 4).

### Task 5: Create API Endpoints for Terminal Sessions (AC: 1, 2, 5, 9, 10) ✅ COMPLETE

- [x] Create controller: `app/controllers/api/v1/terminal_sessions_controller.rb`
  - [x] `GET /api/v1/terminal_sessions` - List all sessions for current user
  - [x] `GET /api/v1/terminal_sessions/:id` - Get session details
  - [x] `POST /api/v1/terminal_sessions` - Start new authentication session
  - [x] `PATCH /api/v1/terminal_sessions/:id` - Update session metadata
  - [x] `POST /api/v1/terminal_sessions/:id/finish_auth` - Mark authentication as finished
  - [x] `POST /api/v1/terminal_sessions/:id/cancel` - Cancel session
  - [x] `DELETE /api/v1/terminal_sessions/:id` - Delete session (if not active)
- [x] Update routes: `config/routes.rb`

**Completed:** Full RESTful API created with all required endpoints. Controller includes proper authorization, error handling, and JSON serialization.

### Task 6: Update Frontend OnboardingPage for Real Terminal (AC: 1, 2, 4, 5, 7) ✅ COMPLETE

- [x] Install xterm.js: `yarn add xterm @xterm/addon-fit @xterm/addon-web-links` (already installed)
- [x] Create AgentAuthTerminal component: `app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx`
- [x] Update OnboardingPage Step 3: Integrated real terminal component
- [x] WebSocket connection to `session.websocket_url`
- [x] Add "Finish Authentication" button (enabled when session is running)
- [x] Polling: Check session state every 2 seconds until `collected`

**Status:** ✅ Complete - Frontend UI fully integrated with backend API. Terminal component uses native WebSocket for low-latency communication.

**Files Created:**
- `web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx`
- `web/app/frontend/features/agent-auth/ui/index.ts`

**Files Updated:**
- `web/app/frontend/pages/onboarding/ui/OnboardingPage.tsx`

### Task 7: Create Frontend RTK Query API for Terminal Sessions (AC: 1, 2, 5) ✅ COMPLETE

- [x] Create API slice: `app/frontend/shared/api/terminalSessionApi.ts`
- [x] Mutations: `createTerminalSession`, `finishAuth`, `cancelSession`, `deleteTerminalSession`
- [x] Queries: `getTerminalSession` (with polling), `listTerminalSessions`
- [x] Create TypeScript types: `app/frontend/entities/terminal-session/model/types.ts`

**Status:** ✅ Complete - Full API implementation with proper types, cache management, and automatic snake_case ↔ camelCase conversion.

### Task 8: Real Docker Integration (AC: 3, 4) ✅ COMPLETE

- [x] Docker images already exist in `docker/` directory (claude-code, cursor-cli, codex, gemini_cli)
- [x] Each includes: agent CLI, ttyd (port 7681), file watcher, bash, git
- [x] Integrated `docker-api` gem in `ContainerService`
- [x] Implemented `start_auth_container` with real Docker API
- [x] Implemented `extract_files` with TAR extraction from containers
- [x] Implemented `stop_container` with graceful shutdown
- [x] Implemented `health_check` with HTTP endpoint polling
- [x] Port management (7681-7799 range) with availability check
- [x] Tmpfs for temporary credentials storage (`/home/claude`)
- [x] Container labels for tracking (session_type, agent_type, user_id)

**Status:** ✅ Complete - Full Docker integration with `docker-api` gem. Containers start with ttyd on dynamic ports, health checks verify readiness, and files are extracted via TAR.

**Files Updated:**
- `web/app/services/container_service.rb` - Real Docker implementation

**Key Features:**
- Dynamic port allocation (7681-7799)
- Health checks with 10-second timeout
- Tmpfs volumes for secure credential storage
- TAR-based file extraction from running containers
- Graceful container shutdown with 5s timeout
- Proper error handling with `ContainerError`

### Task 9: Real Temporal Integration (AC: 2, 5, 6, 9, 10) ✅ COMPLETE

- [x] Temporal server already configured in `docker-compose.yml`
- [x] Temporal UI running on port 8080
- [x] Updated `TemporalService` to support string-based workflow invocation
- [x] Added `start_workflow(workflow_name, **args)` method
- [x] Added `send_signal(workflow_id, signal_name, **args)` method
- [x] Added `cancel_workflow(workflow_id)` method
- [x] Mock mode fallback when `TEMPORAL_ENABLED != true`
- [x] Workflow class lookup by name (`Workflows::AgentAuthWorkflow`)
- [x] UUID-based workflow IDs for uniqueness
- [x] Proper error handling and logging

**Status:** ✅ Complete - Temporal fully integrated with real workflow execution when `TEMPORAL_ENABLED=true`.

**Files Updated:**
- `web/app/services/temporal_service.rb` - Added simple API for terminal sessions

**Key Features:**
- String-based workflow invocation (e.g., `"AgentAuthWorkflow"`)
- Auto-discovery of workflow classes via `constantize`
- Mock mode for development/testing
- Signal support for `authentication_finished`
- Workflow cancellation on user request
- 1-hour execution timeout

### Task 10: Implement Temporal Workflow Trigger from Model Callback (AC: 2) ✅ COMPLETE

- [x] Add callback to TerminalSession model: `after_transition to: :started, do: :start_temporal_workflow`
- [x] Method triggers TemporalService.start_workflow with session details
- [x] Updates session with temporal_workflow_id and temporal_run_id

**Completed:** Callback implemented in `app/models/terminal_session.rb`. When session transitions to `started`, it automatically triggers Temporal workflow (or mock workflow in development).

### Task 10: Write Controller Tests (AC: All) ✅ COMPLETE

- [x] Create test file: `test/controllers/api/v1/terminal_sessions_controller_test.rb`
- [x] Tests for all endpoints:
  - [x] `#index` - List sessions for current user
  - [x] `#show` - Get single session
  - [x] `#create` - Create auth_setup session
  - [x] `#update` - Update metadata
  - [x] `#finish_auth` - Mark as finished
  - [x] `#cancel` - Cancel active session
  - [x] `#destroy` - Delete non-active session
- [x] Tests for validations: agent_type presence, agent_type inclusion, session_type validation
- [x] Tests for authorization: Cannot access other user's sessions
- [x] Tests for state transitions: Cannot finish if not running, cannot cancel if collected, etc.
- [x] All tests passing: 17 runs, 55 assertions, 0 failures

**Completed:** Comprehensive controller test suite created. All tests passing.

### Task 11: Update Documentation (AC: All) ✅ COMPLETE

- [x] Update `ai/architecture.md` with Agent Authentication Infrastructure section
  - [x] TerminalSession model with AASM state machine
  - [x] Temporal workflow flow (Start → Wait Signal → Collect → Stop)
  - [x] ContainerService responsibilities
  - [x] AgentCredential encrypted storage
  - [x] API endpoints
  - [x] Docker images architecture
  - [x] Frontend integration flow (for reference)
  - [x] Testing strategy
- [x] Update `_bmad-output/implementation-artifacts/2-3-configure-claude-code-agent.md` story file

**Completed:** Architecture document updated with comprehensive Agent Authentication Infrastructure section including all components, flows, and rationale.
    - [ ] Stop container via `StopContainerActivity`
    - [ ] Return: 204 No Content
- [ ] Add routes in `config/routes.rb`:
  ```ruby
  namespace :api do
    namespace :v1 do
      resources :terminal_sessions, only: [:create, :show, :destroy] do
        member do
          patch :finish
        end
      end
    end
  end
  ```

### Task 6: Update Frontend OnboardingPage for Real Terminal (AC: 1, 2, 4, 5, 7)

- [ ] Update `OnboardingPage.tsx` Step 3 "Authenticate"
  - [ ] Remove mock "Mark as Authenticated" button
  - [ ] Add states:
    - [ ] `terminalSessions: Record<AgentType, string | null>` - Session IDs
    - [ ] `terminalUrls: Record<AgentType, string | null>` - WebSocket URLs
    - [ ] `sessionStates: Record<AgentType, TerminalSessionState>` - Session states
  - [ ] Implement `handleStartAuthentication(agentType)`:
    - [ ] Call `POST /api/v1/terminal_sessions` with `agent_type`
    - [ ] Store session ID in state
    - [ ] Poll session status every 2 seconds
    - [ ] When `websocket_url` is available, show terminal
  - [ ] Add WebSocket terminal component:
    - [ ] Use library: `xterm` + `xterm-addon-fit` + `xterm-addon-attach`
    - [ ] Connect to `websocket_url` when available
    - [ ] Display terminal in iframe or xterm.js component
  - [ ] Implement `handleFinishAuthentication(agentType)`:
    - [ ] Call `PATCH /api/v1/terminal_sessions/:id/finish`
    - [ ] Continue polling until state becomes `collected`
    - [ ] Update UI to show success checkmark
  - [ ] Update validation logic:
    - [ ] Enable "Continue" button when at least 1 agent has state: `collected`
    - [ ] Show count: "X/Y authenticated"

### Task 7: Create Frontend RTK Query API for Terminal Sessions (AC: 1, 2, 5)

- [ ] Create API: `web/app/frontend/shared/api/terminalSessionApi.ts`
  - [ ] `useCreateTerminalSessionMutation` - POST /api/v1/terminal_sessions
  - [ ] `useGetTerminalSessionQuery` - GET /api/v1/terminal_sessions/:id (with polling)
  - [ ] `useFinishTerminalSessionMutation` - PATCH /api/v1/terminal_sessions/:id/finish
  - [ ] `useCancelTerminalSessionMutation` - DELETE /api/v1/terminal_sessions/:id
- [ ] Create types: `web/app/frontend/entities/terminal-session/model/types.ts`
  - [ ] `ITerminalSession` interface
  - [ ] `TerminalSessionState` type: `'not_started' | 'started' | 'running' | 'finished' | 'collected' | 'failed' | 'cancelled'`
  - [ ] `TerminalSessionType` type: `'auth_setup' | 'agent_session' | 'tool_setup' | 'workflow_step'`

### Task 8: Create Docker Images for Agents (AC: 3, 4)

- [ ] Create single Docker image per agent (4 total images):
  - [ ] `docker/claude-code/Dockerfile` - Claude Code agent
  - [ ] `docker/cursor-cli/Dockerfile` - Cursor CLI agent
  - [ ] `docker/codex/Dockerfile` - OpenAI Codex agent
  - [ ] `docker/gemini-cli/Dockerfile` - Gemini CLI agent
- [ ] Each Dockerfile includes:
  - [ ] Base image: `debian:bookworm-slim` or `alpine:latest`
  - [ ] Install dependencies: `curl`, `bash`, `git`, `ttyd`
  - [ ] Install agent CLI:
    - Claude Code: `claude` CLI (or mock script for MVP)
    - Cursor CLI: `cursor` CLI (or mock script)
    - Codex: `openai` CLI (or mock script)
    - Gemini CLI: `gemini` CLI (or mock script)
  - [ ] Expose ttyd on port 7681
  - [ ] Set entrypoint: `ttyd -p 7681 -W bash`
- [ ] Mock authentication script for MVP (per agent):
  ```bash
  #!/bin/bash
  # Mock claude login for MVP
  echo "Claude Code authentication successful!"
  mkdir -p ~/.claude
  echo "api_key: mock-token-$(date +%s)" > ~/.claude/config
  echo "theme: dark" >> ~/.claude/config
  echo "Authentication complete! Click 'Finish Authentication' in the UI."
  ```
- [ ] Images are reused for both `auth_setup` and `agent_session` types:
  - **auth_setup session:** Container starts with empty home directory
    - User authenticates → creates `~/.claude/config`
    - Artifacts collected → saved to `AgentCredential`
  - **agent_session (future):** Container starts with mounted credentials
    - `AgentCredential.mount_to_container` writes config before session starts
    - Agent CLI is already authenticated
- [ ] Build images:
  ```bash
  docker build -t aixle/claude-code:latest docker/claude-code
  docker build -t aixle/cursor-cli:latest docker/cursor-cli
  docker build -t aixle/codex:latest docker/codex
  docker build -t aixle/gemini-cli:latest docker/gemini-cli
  ```
- [ ] Optionally add to `docker-compose.yml` for local development (pre-built images)

### Task 9: Implement Temporal Workflow Trigger from Model Callback (AC: 2)

- [ ] Update `TerminalSession` model:
  - [ ] Add callback: `after_transition to: :started, do: :start_temporal_workflow`
  - [ ] Method: `start_temporal_workflow`
    - [ ] Call Temporal client to start `AgentAuthWorkflow`
    - [ ] Pass params: `terminal_session_id: self.id`, `user_id: self.user_id`, `agent_type: self.agent_type`
    - [ ] Store workflow ID and run ID in model
    - [ ] Handle errors: transition to `failed` if workflow fails to start
- [ ] Create Temporal client wrapper: `app/services/temporal_service.rb`
  - [ ] Method: `start_workflow(workflow_class, params)`
    - [ ] Connect to Temporal server
    - [ ] Start workflow with unique ID
    - [ ] Return workflow ID and run ID
  - [ ] Method: `send_signal(workflow_id, signal_name, params)`
    - [ ] Send signal to running workflow (e.g., `authentication_finished`)
  - [ ] Method: `cancel_workflow(workflow_id)`
    - [ ] Cancel running workflow

### Task 10: Write Controller Tests (AC: All)

- [ ] Create test: `test/controllers/api/v1/terminal_sessions_controller_test.rb`
  - [ ] Test `POST /api/v1/terminal_sessions` creates session with state `not_started`
  - [ ] Test `POST /api/v1/terminal_sessions` starts Temporal workflow
  - [ ] Test `GET /api/v1/terminal_sessions/:id` returns session details
  - [ ] Test `PATCH /api/v1/terminal_sessions/:id/finish` transitions to `finished`
  - [ ] Test `DELETE /api/v1/terminal_sessions/:id` transitions to `cancelled`
  - [ ] Test authentication requires authenticated user (401)
  - [ ] Test invalid agent_type returns 422
  - [ ] Test finishing non-running session returns error

### Task 11: Update Documentation (AC: All)

- [ ] Update `ai/architecture.md`
  - [ ] Document `TerminalSession` model and state machine
  - [ ] Document Temporal workflow: `AgentAuthWorkflow` with activities
  - [ ] Document `ContainerService` and Docker integration
  - [ ] Document `AgentCredential` storage and encryption
  - [ ] Document session types: `auth_setup` vs `agent_session` vs `tool_setup` vs `workflow_step`
  - [ ] Add architecture diagram for auth flow (optional)
- [ ] Add JSDoc comments to frontend terminal components
- [ ] Update story file with completion notes

## Dev Notes

### Architecture Constraints

**From Story 2.1 & 2.2 Learnings:**
- Onboarding is a mandatory 4-step flow in `web/app/frontend/pages/onboarding/ui/OnboardingPage.tsx`
- User model has `configured_agents: text[]` field to track authenticated agents
- Onboarding completion is tracked via `onboarding_completed_at` timestamp (set by model callback)
- Frontend uses Material-UI for consistent styling
- Backend uses `CurrentUserController` for profile updates
- All tests are controller tests (no model or integration tests)
- Tests run in Docker using `docker-compose exec -T web rails test`

**Temporal Workflow Architecture:**
- **TerminalSession Model** is the central entity with AASM state machine
- State transitions trigger Temporal workflows via model callbacks
- States: `not_started` → `started` → `running` → `finished` → `collected`
- Error states: `failed`, `cancelled`
- Session types distinguish different use cases:
  - `auth_setup` - Agent authentication (Story 2.3)
  - `agent_session` - Agent coding sessions (Epic 4)
  - `tool_setup` - Tool configuration (Epic 8)
  - `workflow_step` - Workflow step execution (Epic 6)

**Authentication Flow with Temporal:**
1. User clicks "Start Authentication" → Frontend calls `POST /api/v1/terminal_sessions`
2. Backend creates `TerminalSession` with state: `not_started`
3. Backend transitions to `started` → triggers `after_transition` callback
4. Callback starts Temporal workflow: `AgentAuthWorkflow`
5. First activity `StartAuthTerminalActivity` starts Docker container
6. Container starts ttyd → activity returns WebSocket URL
7. Session transitions to `running` → Frontend connects to WebSocket
8. User authenticates in terminal, clicks "Finish Authentication"
9. Frontend calls `PATCH /api/v1/terminal_sessions/:id/finish`
10. Backend transitions to `finished` → sends Temporal signal
11. Temporal workflow continues: `CollectArtifactsActivity` extracts config
12. Activity saves artifacts to `AgentCredential` model
13. Session transitions to `collected` → callback adds agent to `user.configured_agents`
14. Temporal workflow completes: `StopContainerActivity` cleans up

**Temporal Workflow Details:**
- Workflow: `AgentAuthWorkflow` orchestrates the auth process
- Activities:
  1. `StartAuthTerminalActivity` - Start container, return WebSocket URL
  2. Wait for signal: `authentication_finished` (blocking)
  3. `CollectArtifactsActivity` - Extract config from container
  4. `StopContainerActivity` - Clean up container
- Workflow ID format: `auth-#{agent_type}-#{user_id}-#{timestamp}`
- Signals: `authentication_finished` sent when user clicks "Finish"
- Cancellation: User can cancel session → Temporal workflow cancelled → container cleaned up

**Docker Infrastructure:**
- Application already uses Docker Compose (see `web/docker-compose.yml`)
- Rails backend runs in `web` container
- PostgreSQL runs in `db` container
- Temporal server runs separately (or use Temporal Cloud)
- **4 Agent Images (not separate auth images):**
  - `aixle/claude-code:latest` - Claude Code agent
  - `aixle/cursor-cli:latest` - Cursor CLI agent
  - `aixle/codex:latest` - OpenAI Codex agent
  - `aixle/gemini-cli:latest` - Gemini CLI agent
- **Single Image, Multiple Use Cases:**
  - Same image used for both `auth_setup` and `agent_session` session types
  - Difference is in volume mounts:
    - **auth_setup:** Empty home directory (user authenticates from scratch)
    - **agent_session:** Pre-mounted credentials (agent is pre-authenticated)
- Authentication containers are ephemeral: created on-demand, destroyed after use
- Use `ContainerService` to manage Docker lifecycle via Docker API

**WebSocket Terminal:**
- ttyd runs inside authentication container on port 7681
- WebSocket URL format: `ws://localhost:<random-port>` (mapped from container)
- Frontend uses `xterm.js` + `xterm-addon-attach` to connect WebSocket
- Real-time terminal interaction (no polling needed for terminal I/O)

**Artifact Collection:**
- After user completes auth, container home directory contains config files
- Example: `~/.claude/config` contains API key and preferences
- `CollectArtifactsActivity` uses `docker cp` to extract files
- Files are saved to `AgentCredential` model with encryption
- **Future Sessions:** Artifacts will be mounted back into agent containers
  - `AgentCredential.mount_to_container(container_id)` writes config before session starts
  - Uses `docker exec` to create files inside running container
  - Agent CLI becomes pre-authenticated (no re-auth needed)

**Image Reuse Strategy:**
- **auth_setup session (Story 2.3):**
  ```ruby
  ContainerService.start_auth_container(user_id, 'claude_code')
  # → Starts aixle/claude-code:latest with empty home directory
  # → User authenticates → creates ~/.claude/config
  # → Artifacts collected → saved to AgentCredential
  ```
- **agent_session (Future Epic 4):**
  ```ruby
  ContainerService.start_agent_container(user_id, 'claude_code', project_id, credentials)
  # → Starts aixle/claude-code:latest
  # → Pre-mounts credentials via AgentCredential.mount_to_container
  # → Agent CLI is already authenticated
  # → User can immediately start coding
  ```

**Session Type Distinctions:**
- **`auth_setup`** (Story 2.3):
  - Purpose: User authentication setup for agent CLI
  - Container: Includes agent CLI + ttyd
  - Duration: User-controlled (until "Finish" clicked)
  - Artifacts: Config files, API tokens
  - Project: Not associated with project (`project_id: null`)
- **`agent_session`** (Future Epic 4):
  - Purpose: Coding session with agent
  - Container: Agent CLI + workspace files + secrets mounted
  - Duration: Until user stops session or workflow completes
  - Artifacts: Generated code, session logs
  - Project: Associated with specific project
- **`tool_setup`** (Future Epic 8):
  - Purpose: Tool configuration and testing
  - Container: Tool runtime + dependencies
  - Duration: Until tool test completes
  - Artifacts: Tool configuration, test results
- **`workflow_step`** (Future Epic 6):
  - Purpose: Workflow step execution
  - Container: Agent CLI + workflow context
  - Duration: Until step completes
  - Artifacts: Step outputs, updated files

**Security Considerations:**
- Docker containers are ephemeral and isolated per user
- Credentials stored in `AgentCredential` with encryption (Rails 7+ encryption or `attr_encrypted`)
- WebSocket URLs are unpredictable (random ports or token-based)
- Containers auto-stop after timeout (5 minutes idle) to prevent resource leaks
- Implement rate limiting to prevent abuse (future enhancement)
- No credentials stored in logs or Temporal history (mask sensitive data)

### Technical Stack

**Backend:**
- Ruby on Rails 8.0
- PostgreSQL (for `TerminalSession`, `AgentCredential` models)
- AASM for state machines (already used for `User`, `Company`)
- Temporal for workflow orchestration (Ruby SDK: `temporalio` gem)
- ActiveJob for async tasks (if needed outside Temporal)
- Docker API integration (Ruby gem: `docker-api` or shell commands)

**Frontend:**
- React 18 with TypeScript
- Material-UI (MUI) for UI components
- RTK Query for API calls (already used in `currentUserApi.ts`)
- TanStack Router for routing
- xterm.js for terminal emulation
  - `xterm` - Core terminal
  - `xterm-addon-fit` - Auto-resize to fit container
  - `xterm-addon-attach` - WebSocket attachment
  - `xterm-addon-web-links` - Clickable links (optional)

**Docker:**
- ttyd for WebSocket-based terminal
- Agent CLIs (Claude Code, Cursor CLI, Codex, Gemini CLI)
- Isolated containers per authentication session
- Volume mounts for home directory persistence during session

**Temporal:**
- Temporal Server (self-hosted or Temporal Cloud)
- Ruby SDK: `temporalio` gem
- Workflows: `app/temporal/workflows/`
- Activities: `app/temporal/activities/`
- Worker: Separate process or integrated with Rails

**Testing:**
- Minitest for controller tests
- FactoryBot for test data (use sequences, no hardcoded values)
- Test in Docker: `docker-compose exec -T web rails test`
- Mock Temporal workflow execution in tests (use test helpers)

### File Structure

**Backend Models:**
- `app/models/terminal_session.rb` - Central session model with AASM
- `app/models/agent_credential.rb` - Encrypted credential storage
- `db/migrate/YYYYMMDDHHMMSS_create_terminal_sessions.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_agent_credentials.rb`

**Backend Controllers:**
- `app/controllers/api/v1/terminal_sessions_controller.rb` - API endpoints
- `config/routes.rb` - Add terminal_sessions routes

**Temporal:**
- `app/temporal/workflows/agent_auth_workflow.rb` - Main workflow
- `app/temporal/activities/start_auth_terminal_activity.rb`
- `app/temporal/activities/collect_artifacts_activity.rb`
- `app/temporal/activities/stop_container_activity.rb`

**Services:**
- `app/services/container_service.rb` - Docker management
- `app/services/temporal_service.rb` - Temporal client wrapper

**Frontend:**
- `web/app/frontend/pages/onboarding/ui/OnboardingPage.tsx` - Update Step 3
- `web/app/frontend/shared/api/terminalSessionApi.ts` - RTK Query API (new)
- `web/app/frontend/entities/terminal-session/model/types.ts` - TypeScript types (new)
- `web/app/frontend/shared/components/WebTerminal.tsx` - xterm.js wrapper (new)

**Docker:**
- `docker/claude-auth/Dockerfile` - Dockerfile for Claude authentication
- `docker/claude-auth/entrypoint.sh` - Entrypoint script to start ttyd
- Repeat for other agents: `docker/cursor-auth/`, `docker/codex-auth/`, etc.

**Tests:**
- `test/controllers/api/v1/terminal_sessions_controller_test.rb`
- `test/factories/terminal_sessions.rb`
- `test/factories/agent_credentials.rb`

### Previous Story Intelligence

**From Story 2.1:**
- Onboarding flow uses `useForm` with `react-hook-form` + `Zod` for validation
- Step navigation uses `currentStep` state (useState)
- Progress bar calculates from `currentStepIndex`
- Validation flags: `isProfileComplete`, `isAgentsSelected`, `isAgentsAuthenticated`
- Edit mode detection: `onboarding_completed_at` is not null
- `useEffect` with `useRef` to prevent duplicate side effects in React Strict Mode

**From Story 2.2:**
- Agent data consolidated into single `AVAILABLE_AGENTS` constant
- `getAgentInfo(agentType)` helper function retrieves agent details
- Agent selection uses `selectedAgents: AgentType[]` state
- Keyboard accessibility implemented: `tabIndex`, `onKeyDown`, ARIA attributes
- Code review revealed importance of DRY principle, AC compliance, and test coverage

**Key Learnings:**
- Always write controller tests (project standard)
- Use `attributes_for` from factories, avoid hardcoded values
- Document state machines and conventions in `ai/architecture.md`
- Implement WCAG 2.1 AA accessibility (keyboard nav, ARIA attributes)
- Run tests in Docker before marking story as review
- State machines with AASM are project pattern (`User`, `Company` models)
- Model callbacks trigger workflows (separation of concerns)

### Git Intelligence

**Recent Commits (last 10):**
```
249d214 add ouput
6f2bcda finish 2-2
d643a6c Merge pull request #2 (feature/platform-admin-company-management)
05dfbbc finish onboarding stepper
0adc66f start next
9c9b088 finish 1-1
67bd529 Merge pull request #1 (feature/models)
438f10c replace opencode with gemini cli
235e577 finish admin and linter
96c3ca0 finish
```

**Patterns Observed:**
- Feature branches merged via Pull Requests
- Commit messages are concise ("finish X", "start X")
- Recent work focused on onboarding stepper (Stories 2.1, 2.2)
- Admin panel and company management already implemented
- Docker infrastructure already exists

### MVP vs Full Implementation

**MVP (Story 2.3):**
- Implement Temporal workflow with signal-based flow
- Implement `TerminalSession` model with AASM state machine
- Mock authentication: Simple script that creates `~/.claude/config` file
- Store artifacts in `AgentCredential` model with basic encryption
- Use xterm.js for terminal UI with WebSocket connection
- Single agent: Claude Code only (Stories 2.4-2.6 for other agents)

**Full Implementation (Future):**
- Real Claude CLI authentication (requires API keys)
- Advanced encryption for credentials (HSM, Vault integration)
- WebSocket authentication and rate limiting
- Session recording and playback
- Multi-agent support (Stories 2.4-2.6)
- Automatic credential rotation (Epic 7)

**Recommendation for Story 2.3:**
- Focus on infrastructure: Temporal + Docker + State machine + WebSocket terminal
- Mock authentication is acceptable (real auth can be added without architecture changes)
- Prove end-to-end flow: UI → API → Temporal → Docker → Artifact collection
- Document session type patterns for future stories

### References

- [Source: ai/epics.md#Epic-2] - Epic 2: Agent Onboarding & Configuration, Story 2.3 requirements
- [Source: _bmad-output/implementation-artifacts/2-1-onboarding-flow-entry.md] - Story 2.1 implementation (onboarding flow structure)
- [Source: _bmad-output/implementation-artifacts/2-2-select-agents-for-configuration.md] - Story 2.2 implementation (agent selection)
- [Source: web/app/frontend/pages/onboarding/ui/OnboardingPage.tsx] - Current onboarding implementation (Step 3 mock)
- [Source: ai/architecture.md#State-Machines] - AASM state machine patterns (User, Company models)
- [Source: ai/architecture.md#User-Onboarding-Flow] - Onboarding completion logic
- [Source: web/docker-compose.yml] - Existing Docker Compose configuration
- [Temporal Ruby SDK](https://github.com/temporalio/sdk-ruby) - Temporal workflow orchestration
- [xterm.js](https://xtermjs.org/) - Terminal emulator for web browsers
- [ttyd](https://github.com/tsl0922/ttyd) - Share terminal over WebSocket

## Dev Agent Record

**Completion Notes (2026-01-24):**

### Backend Implementation Status: PARTIAL COMPLETE ✅

**What was completed:**
1. **TerminalSession Model** - Full AASM state machine implementation with 7 states and proper transitions
2. **Temporal Infrastructure** - Placeholder workflow and activities (mock implementation for MVP)
3. **ContainerService** - Mock Docker management service (real Docker API integration pending)
4. **AgentCredential Model** - Encrypted storage with Rails built-in encryption
5. **API Endpoints** - Full RESTful API (`index`, `show`, `create`, `update`, `finish_auth`, `cancel`, `destroy`)
6. **Controller Tests** - Comprehensive test suite (17 tests, all passing)
7. **Documentation** - Architecture document updated with full Agent Authentication Infrastructure section

**What was deferred:**
1. **Frontend** - xterm.js terminal, WebSocket connection, RTK Query API (Task 6-7)
2. **Docker Images** - 4 agent Dockerfiles with ttyd and CLIs (Task 8)
3. **Real Docker Integration** - ContainerService uses mocks, needs `docker-api` gem integration
4. **Real Temporal Integration** - TemporalService returns mock IDs, needs Temporal server setup

**Decision Rationale:**
User explicitly chose "Option B: Focus on Backend" due to high story complexity and token budget constraints. This allows:
- Complete backend API ready for frontend integration
- Clear separation of concerns (backend can be tested independently)
- Frontend can be implemented in a separate story/iteration
- Docker images can be created during deployment setup

**Architecture Highlights:**
- **State Machine:** 7-state AASM machine (not_started → started → running → stopped → collected) ensures clear workflow progression
- **State Machine in Separate File:** Following project convention, state machine is extracted to `app/state_machines/terminal_session_state_machine.rb`
- **Temporal-Ready:** Infrastructure in place for Temporal workflows (currently mocked for MVP)
- **Encrypted Storage:** AgentCredential uses Rails 7 `encrypts` for secure credential storage
- **Reusable Images:** Single Docker image per agent, reused for both `auth_setup` and `agent_session` types
- **Signal-Based Flow:** Workflow waits for user signal (`authentication_finished`) before artifact collection

**Testing Coverage:**
- 17 controller tests covering all endpoints and error scenarios
- Factories for `TerminalSession` and `AgentCredential` with multiple traits
- All validations and state transitions tested
- Authorization tests (cannot access other user's sessions)

**Next Steps (for future implementation):**
1. Frontend: Implement xterm.js terminal in `OnboardingPage.tsx` Step 3
2. Docker: Create 4 agent Dockerfiles and build images
3. Real Docker: Replace `ContainerService` mocks with `docker-api` gem calls
4. Real Temporal: Configure Temporal server and update `TemporalService`
5. Integration Testing: End-to-end tests with real containers and Temporal

**Files Created:**
- `app/models/terminal_session.rb`
- `app/models/agent_credential.rb`
- `app/controllers/api/v1/terminal_sessions_controller.rb`
- `app/services/container_service.rb`
- `app/services/temporal_service.rb`
- `app/temporal/workflows/agent_auth_workflow.rb`
- `app/temporal/activities/start_auth_terminal_activity.rb`
- `app/temporal/activities/collect_artifacts_activity.rb`
- `app/temporal/activities/stop_container_activity.rb`
- `test/controllers/api/v1/terminal_sessions_controller_test.rb`
- `test/factories/terminal_sessions.rb`
- `test/factories/agent_credentials.rb`
- `db/migrate/20260124121206_create_terminal_sessions.rb`
- `db/migrate/20260124122449_create_agent_credentials.rb`

**Files Modified:**
- `app/models/user.rb` - Added `add_configured_agent` and `remove_configured_agent` methods
- `config/routes.rb` - Added terminal_sessions routes
- `ai/architecture.md` - Added Agent Authentication Infrastructure section

**Database Changes:**
- New table: `terminal_sessions` (with 6 indexes)
- New table: `agent_credentials` (with unique constraint on user_id + agent_type)

**No blockers identified.** Backend is fully functional with mock implementations ready for production services integration.

---

**Story Status:** Backend implementation complete, frontend deferred.
**Recommendation:** Mark story as `review` for backend, create new story for frontend tasks (6-7-8).
**Estimated Remaining Effort:** Frontend (Tasks 6-7-8) = ~150 LOC + Docker setup = 2-3 hours

### Agent Model Used

(To be filled by dev agent during implementation)

### Debug Log References

(To be filled by dev agent)

### Completion Notes List

(To be filled by dev agent after completing implementation)

### File List

**To be Created (Backend only - completed):**
- [x] `app/models/terminal_session.rb` - Central session model with AASM state machine ✅
- [x] `app/models/agent_credential.rb` - Encrypted credential storage for agent auth artifacts ✅
- [x] `app/controllers/api/v1/terminal_sessions_controller.rb` - API endpoints for terminal sessions ✅
- [x] `app/temporal/workflows/agent_auth_workflow.rb` - Temporal workflow (placeholder) ✅
- [x] `app/temporal/activities/start_auth_terminal_activity.rb` - Activity to start container ✅
- [x] `app/temporal/activities/collect_artifacts_activity.rb` - Activity to collect auth artifacts ✅
- [x] `app/temporal/activities/stop_container_activity.rb` - Activity to stop container ✅
- [x] `app/services/container_service.rb` - Service for Docker container management (mock) ✅
- [x] `app/services/temporal_service.rb` - Service for Temporal client operations (mock) ✅
- [x] `test/controllers/api/v1/terminal_sessions_controller_test.rb` - Controller tests (17 tests passing) ✅
- [x] `test/factories/terminal_sessions.rb` - Factory for TerminalSession ✅
- [x] `test/factories/agent_credentials.rb` - Factory for AgentCredential ✅
- [x] `db/migrate/20260124121206_create_terminal_sessions.rb` - Migration for terminal_sessions table ✅
- [x] `db/migrate/20260124122449_create_agent_credentials.rb` - Migration for agent_credentials table ✅

**Deferred (Frontend & Docker - not in backend scope):**
- [ ] `web/app/frontend/shared/api/terminalSessionApi.ts` - RTK Query API for terminal sessions
- [ ] `web/app/frontend/entities/terminal-session/model/types.ts` - TypeScript types for TerminalSession
- [ ] `web/app/frontend/shared/components/WebTerminal.tsx` - xterm.js wrapper component (new)
- [ ] `web/app/frontend/pages/onboarding/ui/OnboardingPage.tsx` - Update Step 3 with real terminal
- [ ] `docker/claude-code/Dockerfile` - Dockerfile for Claude Code agent
- [ ] `docker/cursor-cli/Dockerfile` - Dockerfile for Cursor CLI agent
- [ ] `docker/codex/Dockerfile` - Dockerfile for OpenAI Codex agent
- [ ] `docker/gemini-cli/Dockerfile` - Dockerfile for Gemini CLI agent

**To be Modified (completed):**
- [x] `config/routes.rb` - Add routes for terminal_sessions API ✅
- [x] `ai/architecture.md` - Document TerminalSession state machine, Temporal workflow, session types ✅
- [x] `_bmad-output/implementation-artifacts/2-3-configure-claude-code-agent.md` - Mark tasks complete, add completion notes ✅
- [x] `app/models/user.rb` - Add `add_configured_agent` and `remove_configured_agent` methods ✅

**To be Removed:**
- (None - no files to delete)

---

## Implementation Updates (2026-01-24)

### Architecture Decisions Made

#### 1. Route Token for Session URLs

**Problem:** Using sequential session IDs in URLs (`/s/123/tty`) allows enumeration attacks.

**Solution:** Generate random `route_token` (32 hex chars) at session creation:
- URLs use token: `/t/{route_token}/tty/ws`
- Database lookup: `find_by(route_token: params[:id])`
- Stored in `terminal_sessions.route_token` column

**Migration:** `20260124210000_rename_websocket_token_to_route_token.rb`

#### 2. Agent Credentials Service (Strategy Pattern)

**Problem:** Different agents store credentials in different formats/locations.

**Solution:** Adapter pattern with unified interface:

```
AgentCredentialsService              # Facade
├── Agents::BaseAdapter              # Interface
├── Agents::ClaudeCodeAdapter        # ~/.claude.json
├── Agents::CursorCliAdapter         # ~/.cursor/config.json (stub)
├── Agents::CodexAdapter             # ~/.codex/config.json (stub)
└── Agents::GeminiCliAdapter         # ~/.config/gemini/config.json (stub)
```

**Key Methods:**
- `config_path` - Path to config file
- `home_dir` - Container home directory
- `auth_required_keys` - Keys that indicate auth complete
- `extract_credentials(content)` - Extract credentials for DB storage
- `generate_config(credentials, workflow_config)` - Generate full config

**Files Created:**
- `app/services/agents/base_adapter.rb`
- `app/services/agents/claude_code_adapter.rb`
- `app/services/agents/cursor_cli_adapter.rb`
- `app/services/agents/codex_adapter.rb`
- `app/services/agents/gemini_cli_adapter.rb`
- `app/services/agent_credentials_service.rb`

#### 3. Credential Storage Strategy

**What we store in DB (minimal):**
```json
{
  "oauthAccount": { ... },
  "primaryApiKey": "sk-ant-...",
  "customApiKeyResponses": { ... },
  "userID": "..."
}
```

**What we generate at container startup:**
- Stored credentials + fixed values + workflow-specific config
- Always set `hasTrustDialogAccepted: true`
- Generate `projects` config based on workflow needs

#### 4. Auth Detection via File Watcher

**Problem:** Need to detect when user completes authentication without polling.

**Solution:** Watcher monitors config file and broadcasts WebSocket event:

**Flow:**
1. Container starts with empty home
2. Watcher monitors `AUTH_WATCH_PATH`
3. User authenticates in terminal
4. Agent writes config file
5. Watcher detects change → checks `AUTH_REQUIRED_KEYS`
6. Broadcasts `{ type: 'auth_complete' }` via WebSocket
7. Frontend receives → calls `finishAuth` API
8. Temporal workflow → `CollectArtifactsActivity` → saves credentials

**Environment Variables:**
```bash
SESSION_TYPE=auth_setup          # Only watch for auth_setup
AUTH_WATCH_PATH=/home/claude/.claude.json
AUTH_REQUIRED_KEYS=oauthAccount,primaryApiKey
AGENT_TYPE=claude_code
```

**Watcher Changes:** `docker/shared/watcher/index.js`
- Added `checkAuthComplete(content)` function
- Checks if ANY required key exists (supports nested keys)
- Broadcasts to same WebSocket as file tree updates

#### 5. TerminalSessionWidget Component

**Problem:** Need reusable terminal UI for different pages.

**Solution:** Universal `TerminalSessionWidget` component:

```typescript
<TerminalSessionWidget
  sessionId={123}
  showFileTree={true}
  showFileViewer={true}
  showTerminal={true}
  onSessionUpdate={(session) => ...}
  onAuthComplete={() => ...}
/>
```

**Features:**
- Subscribes to ActionCable for real-time updates
- Displays file tree, file viewer, and terminal (ttyd iframe)
- Resizable panels via `react-resizable-panels`
- Handles `auth_complete` events from watcher

#### 6. ActionCable Integration

**TerminalSessionChannel:**
- Streams session updates on model changes
- Broadcasts `auth_complete` events
- Uses `Api::V1::TerminalSessionSerializer` for data

**useTerminalSessionChannel hook:**
- Handles `session_update` and `auth_complete` messages
- Transforms snake_case to camelCase via `keysToCamelCase`
- Provides `onAuthComplete` callback

#### 7. Traefik Dynamic Routing

**Problem:** Multiple terminal sessions need unique URLs without port conflicts.

**Solution:** Traefik routes by path prefix:
- `/t/{route_token}/tty/*` → container:7681 (ttyd)
- `/t/{route_token}/fs/*` → container:4040 (file watcher)

**Labels (set by ContainerService):**
```ruby
"traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/t/#{route_token}/tty`)"
"traefik.http.routers.#{router_name}-fs.rule" => "PathPrefix(`/t/#{route_token}/fs`)"
```

### Files Modified Today

**Backend:**
- `app/services/container_service.rb` - Pass agent paths to container env
- `app/services/agent_credentials_service.rb` - New facade service
- `app/services/agents/*.rb` - New adapter classes
- `app/models/agent_credential.rb` - Use adapter for operations
- `app/models/terminal_session.rb` - Added `route_token` generation
- `app/temporal/activities/collect_artifacts_activity.rb` - Use adapter service
- `db/migrate/20260124210000_rename_websocket_token_to_route_token.rb` - New migration

**Frontend:**
- `app/frontend/widgets/terminal-session/ui/TerminalSessionWidget.tsx` - New component
- `app/frontend/shared/lib/hooks/useTerminalSessionChannel.ts` - Added auth_complete handling
- `app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx` - Simplified with widget
- `app/frontend/entities/terminal-session/model/types.ts` - Added `routeToken` field

**Docker:**
- `docker/shared/watcher/index.js` - Added auth detection logic

### Completion Summary (2026-01-25)

**Story fully implemented and tested:**

1. **Auth Flow (auth_setup):**
   - User can authenticate Claude Code agent via web terminal
   - Watcher REST API (`/fs/auth`) detects auth completion
   - Frontend polls and shows "Auth detected!" message
   - User clicks "Save Authentication" to finish
   - Credentials extracted and saved encrypted

2. **Agent Session (agent_session):**
   - New session type loads pre-saved credentials
   - `ContainerService.start_agent_container` starts container
   - Credentials written to container after health check
   - Agent CLI is pre-authenticated

3. **Temporal Workflows:**
   - `AgentAuthWorkflow` - handles auth_setup sessions
   - `AgentSessionWorkflow` - handles agent_session sessions

4. **Encryption:**
   - `ActiveSupport::MessageEncryptor` with configurable key
   - Key in `Settings.encryption.credentials_key`

**Files for reference when implementing other agents:**
- `app/services/agents/claude_code_adapter.rb` - adapter example
- `docker/claude-code/Dockerfile` - Docker image example
- `app/services/container_service.rb` - container management

**Next agents (Stories 2.4-2.6):**
- Create adapters following `ClaudeCodeAdapter` pattern
- Update Docker images with agent-specific CLIs
- Test via `/terminal-test` page
