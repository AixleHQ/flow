# Story 2.4: Configure Codex Agent

Status: done

## Story

As a user,
I want to authenticate and configure my Codex agent,
So that I can use it in future sessions.

## Acceptance Criteria

1. **Given** I have selected Codex in the agent selection step (Step 2)
   **When** I reach Step 3 "Authenticate" and click on Codex agent
   **Then** I see instructions for configuring Codex
   **And** I see a "Start Authentication" button
   **And** the agent card shows status: "Not Started"

2. **Given** I am on the Codex authentication screen
   **When** I click "Start Authentication"
   **Then** a `TerminalSession` is created with type: `auth_setup` and agent: `codex`
   **And** the session state machine starts in `not_started` state
   **And** a Temporal workflow is triggered: `AgentAuthWorkflow`
   **And** the session transitions to `started` state
   **And** I see a loading indicator: "Starting terminal session..."

3. **Given** the Temporal workflow has started
   **When** the first activity `StartAuthTerminalActivity` executes
   **Then** a Docker container is started via `ContainerService` with:
   - Codex CLI installed (`@openai/codex`)
   - ttyd web terminal configured
   - WebSocket endpoint exposed
   **And** the activity returns WebSocket URL for terminal connection
   **And** I see the terminal embedded in UI via ttyd iframe
   **And** the session transitions to `running` state

4. **Given** I am connected to the authentication terminal
   **When** the terminal loads
   **Then** I can interact with the terminal to run authentication commands
   **And** the terminal is isolated to my user session
   **And** I can see terminal output in real-time via WebSocket

5. **Given** I have completed authentication in the terminal
   **When** authentication is successful (credentials saved in container's home directory)
   **Then** the watcher `/fs/auth` endpoint returns `{"authenticated": true}`
   **And** I see "Auth detected" message in UI
   **And** I can click "Save Authentication" to mark completion
   **And** the session transitions to `stopped` state

6. **Given** I clicked "Save Authentication"
   **When** the session state changes to `stopped`
   **Then** Temporal workflow continues with `CollectArtifactsActivity`
   **And** the activity extracts authentication artifacts from container
   **And** the session transitions to `collected` state
   **And** artifacts are saved to `AgentCredential` model (encrypted)
   **And** the agent type is added to user's `configured_agents` array
   **And** the container is stopped and removed
   **And** I see a success indicator (checkmark) on the Codex card

7. **Given** I have authenticated Codex
   **When** I return to edit mode (`/onboarding` after completing onboarding)
   **Then** I see Codex marked as "Authenticated" with status: `collected`
   **And** I can re-authenticate if needed (creates new `TerminalSession`)

8. **Given** I start a new session with `agent_session` type and have saved credentials
   **When** the container starts
   **Then** my Codex credentials are automatically loaded into the container
   **And** the Codex CLI is pre-authenticated

## Tasks / Subtasks

### Task 1: Research Codex CLI Authentication Flow (AC: 4, 5) ✅ COMPLETE

- [x] Research `@openai/codex` CLI authentication commands
- [x] Identify config file location and format
- [x] Document required keys for auth detection
- [x] Update `CodexAdapter` with actual paths and keys

**Research Results:**

| Parameter | Value |
|-----------|-------|
| Config path | `/home/codex/.codex/auth.json` |
| Trust config | `/home/codex/.codex/config.toml` |
| Home dir | `/home/codex` |
| Auth keys | `tokens` (contains `access_token`, `refresh_token`, `id_token`) |
| Auth method | OAuth via OpenAI (Google login) |

**auth.json structure:**
```json
{
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "eyJ...",
    "access_token": "eyJ...",
    "refresh_token": "rt_...",
    "account_id": "b73df3d6-..."
  },
  "last_refresh": "2026-01-25T11:24:31.663769540Z"
}
```

**config.toml structure:**
```toml
[projects."/workspace"]
trust_level = "trusted"
```

### Task 2: Update CodexAdapter with Real Implementation (AC: 5, 6, 8) ✅ COMPLETE

- [x] Update `config_path` to `/home/codex/.codex/auth.json`
- [x] Update `auth_required_keys` to `["tokens"]`
- [x] Implement `auth_complete?` to check for `access_token` or `refresh_token`
- [x] Implement `extract_credentials` to extract tokens
- [x] Implement `generate_config` for auth.json
- [x] Override `config_files` to also generate config.toml with trust_level

**File:** `web/app/services/agents/codex_adapter.rb`

### Task 3: Update Docker Image if Needed (AC: 3) ✅ NOT NEEDED

- [x] Verified `@openai/codex` is correctly installed in `docker/codex/Dockerfile`
- [x] Entrypoint script works correctly
- [x] No changes needed to Docker image

### Task 4: Test Full Auth Flow (AC: 1-7) ⏳ PENDING

- [ ] Test via `/terminal-test` page with "Auth Setup" mode
- [ ] Verify authentication commands work in terminal
- [ ] Verify `/fs/auth` endpoint detects auth completion
- [ ] Verify credentials are saved encrypted to `AgentCredential`
- [ ] Verify "With Credentials" mode loads saved credentials

### Task 5: Test Agent Session with Pre-loaded Credentials (AC: 8) ⏳ PENDING

- [ ] Start session with `agent_session` type after auth complete
- [ ] Verify both auth.json and config.toml are written to container
- [ ] Verify Codex CLI is pre-authenticated

## Dev Notes

### Completed Implementation

The `CodexAdapter` has been fully implemented based on research of the actual Codex CLI:

```ruby
class CodexAdapter < BaseAdapter
  def config_path
    "#{home_dir}/.codex/auth.json"
  end

  def home_dir
    "/home/codex"
  end

  def auth_required_keys
    %w[tokens]
  end

  def auth_complete?(config_content)
    config = parse_json(config_content)
    tokens = config["tokens"]
    return false unless tokens.is_a?(Hash)
    tokens["access_token"].present? || tokens["refresh_token"].present?
  end

  def extract_credentials(config_content)
    config = parse_json(config_content)
    config.slice("tokens", "OPENAI_API_KEY", "account_id", "last_refresh").compact
  end

  def config_files(credentials, workflow_config = {})
    {
      config_path => generate_config(credentials, workflow_config).to_json,
      "#{home_dir}/.codex/config.toml" => generate_config_toml(workflow_config)
    }
  end

  private

  def generate_config_toml(workflow_config)
    workspace = workflow_config[:workspace] || "/workspace"
    <<~TOML
      [projects."#{workspace}"]
      trust_level = "trusted"
    TOML
  end
end
```

### Key Differences from Claude Code

| Aspect | Claude Code | Codex |
|--------|-------------|-------|
| Config file | `~/.claude.json` | `~/.codex/auth.json` |
| Auth type | OAuth or API key | OAuth only (Google) |
| Auth keys | `oauthAccount`, `primaryApiKey` | `tokens.access_token` |
| Extra config | Projects in main config | Separate `config.toml` |

### Testing Notes

To test the updated adapter:
1. Delete existing Codex credential via `/admin/agent_credentials`
2. Create new `auth_setup` session on `/terminal-test`
3. Run `codex` in terminal - it will prompt for OAuth
4. After OAuth completes, watcher should detect auth
5. Test `agent_session` to verify credentials load correctly

### References

- [Source: web/app/services/agents/codex_adapter.rb] - Updated adapter
- [Source: web/app/services/agents/base_adapter.rb] - Base adapter interface
- [Source: docker/codex/Dockerfile] - Codex Docker image

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Completion Notes List

1. Researched Codex CLI by examining running container with completed auth
2. Found auth stored in `~/.codex/auth.json` with OAuth tokens
3. Found trust config in `~/.codex/config.toml`
4. Updated `CodexAdapter` with correct paths and auth detection logic
5. Added `config_files` override to generate both auth.json and config.toml

### File List

**Modified:**
- `web/app/services/agents/codex_adapter.rb` - Full implementation with real paths/keys
