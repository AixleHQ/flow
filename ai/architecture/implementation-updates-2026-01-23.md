# Implementation Updates (2026-01-23)

## User Onboarding Flow

**Decision:** Mandatory 4-Step Onboarding with Strict Validation (updated in Story 2.1, verified in Story 2.2)

**Context:**
Users must complete onboarding before accessing the platform. Onboarding **cannot be skipped** and includes:
1. **Step 1 - Your Profile:** Selecting position (Dev, QA, PM/PO/BA, Designer, CTO) and preferred agent language
2. **Step 2 - Select Agents:** Selecting at least one AI agent (Claude Code, Cursor CLI, Codex, Gemini CLI)
   - Each agent displays name and detailed description
   - Visual states: default, selected (highlighted border), hover
   - Validation: at least 1 agent required to proceed
   - State persists across step navigation (back/forward)
3. **Step 3 - Authenticate:** Authenticating at least one selected agent
4. **Step 4 - Complete:** Reviewing and confirming setup

**No progress is saved** - users must complete all steps in one session.

**Edit Mode:** Users who have completed onboarding can return to `/onboarding` to edit their profile, position, language, and agents. Configured agents are pre-selected in Step 2.

**Solution:**
Implemented automatic `onboarding_completed_at` tracking via `before_validation` callback in User model:

```ruby
# app/models/user.rb
has_secure_password validations: false

# Constants
AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
POSITIONS = %w[qa pm_po_ba dev designer].freeze
AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

# Database fields
# - configured_agents: text[] (PostgreSQL array)
# - position: string
# - preferred_agent_language: string
# - onboarding_completed_at: datetime

# Validations
validate :at_least_one_agent_after_onboarding
validate :configured_agents_valid

# Callbacks
before_validation :set_onboarding_completed_at, if: :onboarding_ready?

private

def onboarding_ready?
  return false if super_admin? # Super admins don't need onboarding
  return false if onboarding_completed? # Already completed

  # Onboarding is ready when position, language, and at least one agent are configured
  position.present? &&
    preferred_agent_language.present? &&
    has_configured_agents?
end

def has_configured_agents?
  configured_agents.present? && configured_agents.any?
end

def set_onboarding_completed_at
  self.onboarding_completed_at = Time.current
end
```

**Rationale:**
1. **Single Responsibility:** Controller only updates user attributes, model handles completion logic
2. **Mandatory Onboarding:** No "Skip" button - ensures all users have proper configuration before platform access
3. **Consistency:** Onboarding is always marked complete when ALL requirements are met (position + language + agent)
4. **Rails Convention:** Business logic lives in models, not controllers
5. **Data Integrity:** PostgreSQL array ensures valid storage, validations ensure valid values
6. **4-Step Flow:** Clear progression through profile → agents → authentication → completion (updated in Story 2.1)
7. **Edit Mode:** Allows users to update their profile and agents after initial completion

**API Changes:**
- `PATCH /api/v1/current_user` - accepts `position`, `preferred_agent_language`, and `configured_agents` (array)
- Backend automatically sets `onboarding_completed_at` when all three fields are valid and present
- Frontend doesn't send or manage `onboarding_completed_at`

**Database Schema:**
```sql
ALTER TABLE users ADD COLUMN configured_agents text[] DEFAULT '{}';
```

**Testing:**
- Controller tests verify position/language/agents update
- Model tests verify automatic completion only when all fields present
- Validation tests ensure at least one agent required after onboarding

---

## Agent Authentication Infrastructure (Story 2.3)

**Decision:** Terminal Sessions with State Machines + Temporal Workflows + Docker Containers

**Context:**
Users need to authenticate agent CLIs (Claude Code, Cursor CLI, Codex, Gemini CLI) during onboarding (Step 3). Authentication happens via interactive web terminals where users log into the agent CLI. After authentication, credentials are extracted from the container and stored encrypted for future sessions.

**Architecture Components:**

### 1. TerminalSession Model (AASM State Machine)

```ruby
# app/models/terminal_session.rb
class TerminalSession < ApplicationRecord
  include AASM

  belongs_to :user
  belongs_to :project, optional: true  # Nullable for auth_setup sessions

  # Fields:
  # - session_type: string (auth_setup, agent_session, tool_setup, workflow_step)
  # - agent_type: string (claude_code, cursor_cli, codex, gemini_cli)
  # - state: string (not_started, started, running, stopped, collected, failed, cancelled)
  # - temporal_workflow_id: string
  # - temporal_run_id: string
  # - container_id: string
  # - websocket_url: string
  # - artifacts_path: string (reference to AgentCredential ID)
  # - error_message: text
  # - metadata: jsonb
  # - timestamps: started_at, finished_at, collected_at

  aasm column: :state do
    state :not_started, initial: true
    state :started         # Container starting
    state :running         # Container ready, user authenticating
    state :stopped         # User clicked "Finish Auth"
    state :collected       # Artifacts extracted and stored
    state :failed
    state :cancelled

    event :start do
      transitions from: :not_started, to: :started, after: :start_temporal_workflow
    end

    event :mark_running do
      transitions from: :started, to: :running
    end

    event :stop do
      transitions from: :running, to: :stopped
    end

    event :collect do
      transitions from: :stopped, to: :collected, after: :update_user_configured_agents
    end

    event :fail do
      transitions from: %i[not_started started running stopped], to: :failed, after: :cleanup_resources
    end

    event :cancel do
      transitions from: %i[not_started started running], to: :cancelled, after: :cleanup_resources
    end
  end

  def update_user_configured_agents
    return unless session_type == "auth_setup" && agent_type.present?

    user.add_configured_agent(agent_type) unless user.configured_agents.include?(agent_type)
    update!(collected_at: Time.current)
  end
end
```

### 2. Temporal Workflow (AgentAuthWorkflow)

**Flow:**
1. **StartAuthTerminalActivity:** Start Docker container with ttyd web terminal
   - Image: `palad/claude-code:latest` (or cursor-cli, codex, gemini-cli)
   - Home directory: tmpfs (empty, no credentials mounted)
   - Expose WebSocket on random port (7681-7699)
   - Wait for health check
   - Return: `container_id`, `websocket_url`

2. **Wait for Signal:** Workflow blocks until user sends `authentication_finished` signal
   - User authenticates in terminal (e.g., `claude login`)
   - User clicks "Finish Authentication" button in UI
   - Frontend calls `POST /api/v1/terminal_sessions/:id/finish_auth`
   - Backend triggers AASM transition: `session.finish!`
   - Backend sends Temporal signal: `TemporalService.send_signal(workflow_id, :authentication_finished)`

3. **CollectArtifactsActivity:** Extract credentials from container
   - Use `docker cp` or `docker exec` to extract config files
   - Example paths:
     - Claude Code: `~/.claude/config`
     - Cursor CLI: `~/.cursor/config`
     - Codex: `~/.openai/config`
     - Gemini CLI: `~/.gemini/config`
   - Create `AgentCredential` record with encrypted config data
   - Trigger AASM transition: `session.collect!`

4. **StopContainerActivity:** Stop and remove container

**Pseudocode:**
```ruby
# app/temporal/workflows/agent_auth_workflow.rb
module Workflows
  class AgentAuthWorkflow
    def execute(terminal_session_id:, user_id:, agent_type:)
      # Step 1: Start container
      container_info = StartAuthTerminalActivity.execute(
        terminal_session_id: terminal_session_id,
        user_id: user_id,
        agent_type: agent_type
      )

      # Step 2: Wait for user signal (blocking)
      wait_for_signal(:authentication_finished)

      # Step 3: Collect artifacts
      artifacts = CollectArtifactsActivity.execute(
        terminal_session_id: terminal_session_id,
        container_id: container_info[:container_id],
        agent_type: agent_type
      )

      # Step 4: Cleanup
      StopContainerActivity.execute(
        container_id: container_info[:container_id]
      )

      { status: :completed, artifacts: artifacts }
    rescue StandardError => e
      session = TerminalSession.find(terminal_session_id)
      session.update!(error_message: e.message)
      session.fail!
      raise
    end
  end
end
```

### 3. ContainerService (Docker Management)

**Responsibilities:**
- Start authentication containers with empty home directories
- Start agent session containers with mounted credentials (Epic 4)
- Extract files from containers
- Stop and remove containers
- Health checks

**Key Methods:**
```ruby
# app/services/container_service.rb
class ContainerService
  def self.start_auth_container(user_id, agent_type)
    # Select image: palad/claude-code:latest, palad/cursor-cli:latest, etc.
    image = image_for_agent(agent_type)

    # Start container with empty home (tmpfs)
    container = Docker::Container.create(
      'Image' => image,
      'name' => "auth-#{agent_type}-#{user_id}-#{Time.now.to_i}",
      'ExposedPorts' => { '7681/tcp' => {} },
      'HostConfig' => {
        'PortBindings' => { '7681/tcp' => [{ 'HostPort' => random_port.to_s }] },
        'Tmpfs' => { '/home/agent' => 'rw,size=100m' }  # Empty home directory
      }
    )
    container.start

    { container_id: container.id, websocket_url: "ws://localhost:#{port}" }
  end

  def self.start_agent_container(user_id, agent_type, project_id, credentials)
    # (Epic 4) Same image, but mount credentials
    # AgentCredential.mount_to_container(container_id) will write config files
  end

  def self.extract_files(container_id, paths)
    result = {}
    paths.each do |path|
      temp_file = "/tmp/#{SecureRandom.hex}"
      system("docker cp #{container_id}:#{path} #{temp_file}")
      result[path] = File.read(temp_file) if File.exist?(temp_file)
      File.delete(temp_file) if File.exist?(temp_file)
    end
    result
  end

  def self.stop_container(container_id)
    container = Docker::Container.get(container_id)
    container.stop
    container.remove
  end
end
```

### 4. AgentCredential Model (Encrypted Storage)

**Purpose:** Store agent authentication artifacts securely for future sessions

```ruby
# app/models/agent_credential.rb
class AgentCredential < ApplicationRecord
  belongs_to :user

  # Fields:
  # - agent_type: string (unique per user)
  # - encrypted_config_data: text (Rails built-in encryption)
  # - metadata: jsonb (collected_at, artifact_count, etc.)
  # - timestamps: last_used_at, expires_at

  encrypts :encrypted_config_data

  validates :agent_type, uniqueness: { scope: :user_id }

  # Create from extracted artifacts
  def self.from_artifacts(user_id, agent_type, artifacts_hash)
    credential = find_or_initialize_by(user_id: user_id, agent_type: agent_type)
    credential.config_data = artifacts_hash
    credential.metadata = {
      collected_at: Time.current,
      artifact_count: artifacts_hash.keys.size
    }
    credential.save!
    credential
  end

  # Get/set config data (auto-encrypted)
  def config_data
    JSON.parse(encrypted_config_data) rescue {}
  end

  def config_data=(hash)
    self.encrypted_config_data = hash.to_json
  end

  # Mount credentials to agent session container (Epic 4)
  def mount_to_container(container_id)
    config_data.each do |path, content|
      expanded_path = path.gsub("~", "/home/agent")
      dir = File.dirname(expanded_path)

      system("docker exec #{container_id} mkdir -p #{dir}")
      IO.popen("docker exec -i #{container_id} tee #{expanded_path} > /dev/null", "w") { |pipe| pipe.write(content) }
    end

    touch(:last_used_at)
  end
end
```

### 5. API Endpoints

**Routes:**
```ruby
# config/routes.rb
namespace :api, defaults: { format: :json } do
  namespace :v1 do
    resources :terminal_sessions, only: %i[index show create update destroy] do
      member do
        post :finish_auth   # User finished authentication
        post :cancel        # Cancel active session
      end
    end
  end
end
```

**Controller:**
```ruby
# app/controllers/api/v1/terminal_sessions_controller.rb
module Api::V1
  class TerminalSessionsController < ApplicationController
    before_action :authenticate_user!

    # POST /api/v1/terminal_sessions
    def create
      session = current_user.terminal_sessions.build(session_params)

      if session.save
        session.start! if session.may_start?  # Triggers Temporal workflow
        render json: { data: session_json(session) }, status: :created
      else
        render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/v1/terminal_sessions/:id/finish_auth
    def finish_auth
      @session.finish!

      # Send signal to Temporal workflow
      if @session.temporal_workflow_id.present?
        TemporalService.send_signal(@session.temporal_workflow_id, :authentication_finished)
      end

      render json: { data: session_json(@session), message: "Authentication finished, collecting artifacts..." }
    end
  end
end
```

### 6. Docker Images (4 total)

**Single Image per Agent (reused for auth and sessions):**
- `palad/claude-code:latest` - Claude Code agent
- `palad/cursor-cli:latest` - Cursor CLI agent
- `palad/codex:latest` - OpenAI Codex agent
- `palad/gemini-cli:latest` - Gemini CLI agent

**Image Structure:**
```dockerfile
# docker/claude-code/Dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl bash git ttyd && \
    rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Expose ttyd on port 7681
EXPOSE 7681

# Start ttyd web terminal
ENTRYPOINT ["ttyd", "-p", "7681", "-W", "bash"]
```

**Usage:**
- **auth_setup session:** Container starts with empty home directory (tmpfs)
  - User authenticates → creates `~/.claude/config`
  - Artifacts collected → saved to `AgentCredential`
- **agent_session (future):** Container starts with mounted credentials
  - `AgentCredential.mount_to_container` writes config before session starts
  - Agent CLI is pre-authenticated

### 7. Frontend Integration (Not in Backend Scope)

**Onboarding Step 3 Flow:**
1. User selects agent (e.g., Claude Code)
2. Click "Start Authentication" → `POST /api/v1/terminal_sessions` with `session_type: "auth_setup"`, `agent_type: "claude_code"`
3. Backend creates session → starts Temporal workflow → returns `websocket_url`
4. Frontend embeds xterm.js terminal → connects to WebSocket
5. User authenticates in terminal (e.g., `claude login`)
6. User clicks "Finish Authentication" → `POST /api/v1/terminal_sessions/:id/finish_auth`
7. Backend sends Temporal signal → artifacts collected → session marked `collected`
8. Frontend polls `GET /api/v1/terminal_sessions/:id` until `state: "collected"`
9. User proceeds to next agent or Step 4

**Rationale:**
1. **State Machine Clarity:** AASM provides clear state transitions with callbacks and guards
2. **Temporal Orchestration:** Long-running workflows with signal-based user interaction (wait for "Finish" button)
3. **Docker Isolation:** Each authentication session in isolated container, no cross-contamination
4. **Credential Security:** Encrypted at rest (Rails `encrypts`), never exposed in API responses
5. **Reusable Images:** Same Docker image for auth and future agent sessions (mount determines auth state)
6. **Scalability:** Temporal handles workflow persistence, retries, and failure recovery
7. **Audit Trail:** All state transitions and timestamps logged in `terminal_sessions` table

**Testing Strategy:**
- Controller tests: Create session, finish auth, cancel, state transitions
- Model tests: AASM transitions, validation, callbacks
- Service tests: ContainerService (mock Docker API), TemporalService (mock workflows)
- Integration tests: Full flow from create → start → finish → collect (with mocked Docker/Temporal)

---

## Agent Credentials Service Architecture (Story 2.3 - Updated 2026-01-25)

**Decision:** Strategy Pattern for Agent-Specific Credential Handling

**Context:**
Different AI agents (Claude Code, Cursor CLI, Codex, Gemini CLI) store credentials in different locations and formats. We need a unified interface for:
- Extracting credentials after authentication
- Generating config files for new containers
- Detecting when authentication is complete
- Loading credentials into agent session containers

**Architecture Components:**

### 1. Adapter Pattern (Strategy)

```
AgentCredentialsService              # Facade - selects adapter by agent_type
├── Agents::BaseAdapter              # Abstract interface
├── Agents::ClaudeCodeAdapter        # Claude Code implementation
├── Agents::CursorCliAdapter         # Cursor CLI (stub)
├── Agents::CodexAdapter             # Codex (stub)
└── Agents::GeminiCliAdapter         # Gemini CLI (stub)
```

**Base Adapter Interface:**
```ruby
# app/services/agents/base_adapter.rb
module Agents
  class BaseAdapter
    def config_path           # Path to config file inside container
    def home_dir              # Home directory (/home/claude, /home/cursor, etc.)
    def auth_watch_path       # Path to watch for auth completion
    def auth_required_keys    # Keys that indicate auth is complete
    def auth_complete?(content)     # Check if auth is complete
    def extract_credentials(content) # Extract credentials for DB storage
    def generate_config(credentials, workflow_config) # Generate full config
    def config_files(credentials, workflow_config)    # All files to write
  end
end
```

**To add a new agent:**
1. Create `app/services/agents/{agent_name}_adapter.rb`
2. Implement all methods from `BaseAdapter`
3. Add to `ADAPTERS` hash in `AgentCredentialsService`
4. Create Docker image in `docker/{agent_name}/`
5. Add agent type to `AVAILABLE_AGENTS` in User model

### 2. Credential Storage Strategy

**What we store in DB (AgentCredential.config_data):**
```json
{
  "oauthAccount": { "accountUuid": "...", "emailAddress": "...", ... },
  "primaryApiKey": "sk-ant-...",
  "customApiKeyResponses": { "approved": [...], "rejected": [] },
  "userID": "..."
}
```

**Encryption:** Uses `ActiveSupport::MessageEncryptor` with key from `Settings.encryption.credentials_key`

**What we generate at container startup:**
```json
{
  // From DB (credentials)
  "oauthAccount": { ... },
  "primaryApiKey": "...",

  // Fixed values
  "installMethod": "global",
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "2.1.14",

  // Generated from workflow config
  "projects": {
    "/workspace": {
      "allowedTools": [],        // From workflow config
      "mcpServers": {},          // From workflow config
      "hasTrustDialogAccepted": true  // Always true
    }
  }
}
```

### 3. Two Session Types

**auth_setup (Onboarding - Story 2.3):**
- Container starts with empty home directory (tmpfs)
- User authenticates in terminal (e.g., `claude login`)
- Watcher detects auth completion via `/fs/auth` REST API (polling)
- Frontend calls `finishAuth` API
- Temporal workflow collects and saves encrypted credentials
- User's `configured_agents` array is updated

**agent_session (Working sessions - Story 2.3+):**
- Container starts with empty home directory
- After container health check, credentials are loaded via `write_to_container`
- Agent CLI is pre-authenticated (no re-auth needed)
- User can immediately start working

### 4. Auth Detection via File Watcher REST API

**Flow:**
```
1. Container starts with empty home
2. Frontend polls /fs/auth endpoint every 2 seconds
3. User authenticates in terminal (e.g., `claude login`)
4. Agent writes config file
5. Watcher checks AUTH_REQUIRED_KEYS in config
6. Returns { "authenticated": true }
7. Frontend shows "Auth detected!" message
8. User clicks "Save Authentication" button
9. Frontend calls finishAuth API
10. Temporal workflow → CollectArtifactsActivity → saves credentials
```

**Watcher REST API:**
```javascript
// GET /fs/auth
// Returns: { "authenticated": true/false }

function checkAuthComplete(configContent) {
  const config = JSON.parse(configContent);
  return AUTH_REQUIRED_KEYS.some(key => {
    const value = key.split('.').reduce((obj, k) => obj?.[k], config);
    return value !== undefined && value !== null && value !== '';
  });
}
```

**Environment Variables (passed from ContainerService):**
```bash
SESSION_TYPE=auth_setup          # Only check auth for auth_setup sessions
AUTH_WATCH_PATH=/home/claude/.claude.json
AUTH_REQUIRED_KEYS=oauthAccount,primaryApiKey  # Comma-separated
AGENT_TYPE=claude_code
```

### 5. Container Service Methods

**For auth_setup:**
```ruby
ContainerService.start_auth_container(
  user_id,
  agent_type,
  session_id: session.id,
  route_token: session.route_token
)
# Returns: { container_id:, websocket_url:, watcher_url: }
```

**For agent_session:**
```ruby
ContainerService.start_agent_container(
  user_id,
  agent_type,
  session_id: session.id,
  route_token: session.route_token,
  credential: user.agent_credentials.find_by(agent_type: agent_type)
)
# After container starts, calls credential.write_to_container(container_id)
```

### 6. Temporal Workflows

**AgentAuthWorkflow (auth_setup):**
1. `StartAuthTerminalActivity` - Start container with empty home
2. Wait for `authentication_finished` signal
3. `CollectArtifactsActivity` - Extract and save credentials
4. `StopContainerActivity` - Cleanup

**AgentSessionWorkflow (agent_session):**
1. `StartAgentSessionActivity` - Start container with credentials loaded
2. Wait for `session_finished` signal
3. `StopContainerActivity` - Cleanup

### 7. Frontend Components

**AgentAuthTerminal (Onboarding):**
```typescript
// Polls /fs/auth for auth status
// Shows "Auth detected!" when authenticated
// User clicks "Save Authentication" to finish
<AgentAuthTerminal
  agentType="claude_code"
  onAuthComplete={() => navigateToNextStep()}
/>
```

**TerminalTestPage (Testing):**
```typescript
// Toggle between auth_setup and agent_session modes
// Supports all 4 agent types
// Shows file tree, file viewer, and terminal
```

### 8. Adding New Agent Types

**Checklist:**
1. **Adapter:** Create `app/services/agents/{agent}_adapter.rb`
   - `config_path` - Where agent stores config
   - `home_dir` - Container home directory
   - `auth_required_keys` - Keys indicating auth complete
   - `extract_credentials` - What to save in DB
   - `generate_config` - Full config for container

2. **Docker Image:** Create `docker/{agent}/Dockerfile`
   - Base: `palad/agent-base:latest`
   - Install agent CLI
   - Copy any agent-specific files

3. **Constants:** Add to `User::AVAILABLE_AGENTS`

4. **Test:** Use `/terminal-test` page to verify auth flow

**Example (Claude Code):**
```ruby
# app/services/agents/claude_code_adapter.rb
module Agents
  class ClaudeCodeAdapter < BaseAdapter
    def config_path
      "/home/claude/.claude.json"
    end

    def home_dir
      "/home/claude"
    end

    def auth_required_keys
      %w[oauthAccount primaryApiKey]
    end

    def extract_credentials(content)
      config = JSON.parse(content)
      {
        "oauthAccount" => config["oauthAccount"],
        "primaryApiKey" => config["primaryApiKey"],
        "customApiKeyResponses" => config["customApiKeyResponses"],
        "userID" => config["userID"]
      }.compact
    end

    def generate_config(credentials, workflow_config = {})
      credentials.merge(
        "installMethod" => "global",
        "hasCompletedOnboarding" => true,
        "hasTrustDialogAccepted" => true,
        "projects" => {
          "/workspace" => {
            "allowedTools" => workflow_config[:allowed_tools] || [],
            "mcpServers" => workflow_config[:mcp_servers] || {},
            "hasTrustDialogAccepted" => true
          }
        }
      )
    end
  end
end
```

---

**Architecture Status:** IMPLEMENTED ✅

**Tested Features:**
- Auth flow with Claude Code agent
- Credential collection and encryption
- Agent session with pre-loaded credentials
- File watcher REST API for auth detection

**Document Maintenance:** Update this architecture when major technical decisions are made during implementation.

---
