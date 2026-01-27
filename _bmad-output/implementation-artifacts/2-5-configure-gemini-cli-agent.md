# Story 2.5: Configure Gemini CLI Agent

Status: ready-for-dev

## Story

As a user,
I want to authenticate and configure my Gemini CLI agent,
So that I can use it in future sessions.

## Acceptance Criteria

1. **Given** I have selected Gemini CLI in the agent selection step
   **When** I reach the Gemini CLI configuration step
   **Then** I see instructions for configuring Gemini CLI

2. **Given** I am on the Gemini CLI configuration step
   **When** I view the embedded terminal
   **Then** I can authenticate with Gemini CLI in an embedded terminal

3. **Given** I have authenticated in the terminal
   **When** the watcher detects authentication is complete
   **Then** I see "Auth detected!" indicator and "Save Authentication" button becomes enabled

4. **Given** authentication is detected
   **When** I click "Save Authentication"
   **Then** my Gemini CLI credentials are encrypted and saved to AgentCredential

5. **Given** I have saved credentials
   **When** I start an agent_session with Gemini CLI
   **Then** the container starts with pre-loaded credentials and Gemini CLI is pre-authenticated

6. **Given** I want to skip Gemini CLI
   **When** I click "Skip" on the configuration step
   **Then** I can proceed to the next agent or onboarding step

## Tasks / Subtasks

- [ ] Task 1: Research Gemini CLI configuration (AC: #1)
  - [ ] 1.1 Start a Gemini CLI container and authenticate manually
  - [ ] 1.2 Identify config file paths (e.g., `~/.gemini/config`, `~/.config/gemini/`)
  - [ ] 1.3 Identify required keys for auth detection (e.g., `api_key`, `oauth_token`)
  - [ ] 1.4 Document findings in this story

- [ ] Task 2: Implement GeminiCliAdapter (AC: #2, #3, #4)
  - [ ] 2.1 Update `app/services/agents/gemini_cli_adapter.rb` with correct:
    - `config_path` - actual path to Gemini config
    - `home_dir` - `/home/gemini`
    - `auth_required_keys` - keys indicating auth complete
    - `auth_complete?` - check logic
    - `extract_credentials` - what to save
    - `generate_config` - full config for container
  - [ ] 2.2 If needed, override `config_files` for multiple config files

- [ ] Task 3: Update Docker image if needed (AC: #5)
  - [ ] 3.1 Review `docker/gemini-cli/Dockerfile`
  - [ ] 3.2 Ensure Gemini CLI is properly installed
  - [ ] 3.3 Ensure entrypoint starts ttyd correctly
  - [ ] 3.4 Rebuild image: `docker build -t palad/gemini-cli:latest docker/gemini-cli/`

- [ ] Task 4: Test auth flow (AC: #1, #2, #3, #4)
  - [ ] 4.1 Navigate to `/terminal-test` page
  - [ ] 4.2 Select Gemini CLI + Auth Setup mode
  - [ ] 4.3 Authenticate in terminal
  - [ ] 4.4 Verify watcher detects auth (polls `/fs/auth`)
  - [ ] 4.5 Click "Save Authentication"
  - [ ] 4.6 Verify AgentCredential saved in admin panel

- [ ] Task 5: Test agent session (AC: #5)
  - [ ] 5.1 Navigate to `/terminal-test` page
  - [ ] 5.2 Select Gemini CLI + Agent Session mode
  - [ ] 5.3 Verify container starts with pre-loaded credentials
  - [ ] 5.4 Verify Gemini CLI is pre-authenticated

## Dev Notes

### Architecture Reference
See [architecture.md](../../../ai/architecture.md) section "Agent Credentials Service Architecture" for:
- Adapter pattern implementation
- Two session types (auth_setup vs agent_session)
- Auth detection via watcher REST API
- Credential storage strategy

### Existing Implementations to Follow

**ClaudeCodeAdapter** (`web/app/services/agents/claude_code_adapter.rb`):
- `config_path`: `/home/claude/.claude.json`
- `auth_required_keys`: `['oauthAccount', 'primaryApiKey']`
- Generates `config.json` + `settings.json`

**CodexAdapter** (`web/app/services/agents/codex_adapter.rb`):
- `config_path`: `/home/codex/.codex/auth.json`
- `auth_required_keys`: `['tokens']`
- Generates `auth.json` + `config.toml`

**CursorCliAdapter** (`web/app/services/agents/cursor_cli_adapter.rb`):
- `config_path`: `/home/cursor/.config/cursor/auth.json`
- `auth_required_keys`: `['accessToken']`
- Generates `auth.json` + `cli-config.json` + `.workspace-trusted`
- Overrides `tmpfs_paths` to preserve installed binary

### Research Questions

1. Where does Gemini CLI store its config?
   - Possible: `~/.gemini/`, `~/.config/gemini/`, `~/.google/`
2. What keys indicate authentication is complete?
   - Possible: `api_key`, `oauth_token`, `access_token`, `credentials`
3. Does Gemini CLI require any special CLI flags for non-interactive mode?
4. Does Gemini CLI install binaries that need to survive tmpfs mount?

### AgentSetting Model (Implemented)

New model `AgentSetting` for storing user-specific agent configuration BEFORE authentication.
This solves the problem of agents like Gemini CLI that need env vars (GOOGLE_PROJECT_ID) at container startup.

**Flow:**
1. User selects Gemini CLI on onboarding
2. UI checks if agent requires settings via `GET /api/v1/agent_settings/fields/gemini_cli`
3. If required, shows settings form BEFORE starting terminal
4. User fills in GOOGLE_PROJECT_ID, saves via `POST /api/v1/agent_settings`
5. Settings saved to `AgentSetting` model
6. User clicks "Start Authentication" → container starts with env vars from settings
7. User authenticates → credentials saved to `AgentCredential`

**Architecture:**

1. **AgentSetting Model** (`web/app/models/agent_setting.rb`):
   - `user_id`, `agent_type`, `settings` (jsonb)
   - Unique constraint on `[user_id, agent_type]`
   - Methods: `env_vars`, `validate_settings`, `complete?`

2. **BaseAdapter** (`web/app/services/agents/base_adapter.rb`):
   - `settings_fields` - field definitions for UI
   - `env_vars_from_settings(settings)` - convert to env vars
   - `validate_settings(settings)` - validate required fields
   - `requires_settings?` - check if agent needs pre-config

3. **GeminiCliAdapter** (`web/app/services/agents/gemini_cli_adapter.rb`):
   - `settings_fields` returns fields for GOOGLE_PROJECT_ID, GOOGLE_REGION
   - `env_vars_from_settings` converts to env var names

4. **AgentSettingsController** (`web/app/controllers/api/v1/agent_settings_controller.rb`):
   - `GET /fields/:agent_type` - get field definitions
   - `POST /` - create/update settings
   - `GET /:agent_type` - get saved settings

5. **ContainerService** (`web/app/services/container_service.rb`):
   - `start_auth_container` and `start_agent_container` load `AgentSetting`
   - Pass env vars via adapter's `env_vars_from_settings`

6. **AgentAuthTerminal** (`web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx`):
   - 3-step flow: settings → terminal → completed
   - Loads field definitions from API
   - Shows settings form if `requiresSettings`
   - Saves settings before starting terminal

7. **agentSettingsApi** (`web/app/frontend/shared/api/agentSettingsApi.ts`):
   - RTK Query endpoints for settings CRUD

### Key Files to Modify

1. `web/app/services/agents/gemini_cli_adapter.rb` - Main implementation
2. `web/app/services/container_service.rb` - If special commands needed
3. `docker/gemini-cli/Dockerfile` - If image updates needed
4. `docker/gemini-cli/entrypoint.sh` - If entrypoint updates needed

### Project Structure Notes

- Adapter location: `web/app/services/agents/`
- Docker images: `docker/{agent_name}/`
- Test page: `/terminal-test` (frontend)
- Admin for credentials: `/admin/agent_credentials`

### References

- [Architecture: Agent Credentials Service](../../../ai/architecture.md#agent-credentials-service-architecture-story-23---updated-2026-01-25)
- [ClaudeCodeAdapter](../../../web/app/services/agents/claude_code_adapter.rb)
- [CodexAdapter](../../../web/app/services/agents/codex_adapter.rb)
- [CursorCliAdapter](../../../web/app/services/agents/cursor_cli_adapter.rb)
- [BaseAdapter](../../../web/app/services/agents/base_adapter.rb)

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
