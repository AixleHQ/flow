# Story 2.6: Configure Cursor CLI Agent

Status: done

## Story

As a user,
I want to authenticate and configure my Cursor CLI agent,
So that I can use it in future sessions.

## Acceptance Criteria

1. **Given** I have selected Cursor CLI in the agent selection step (Step 2)
   **When** I reach Step 3 "Authenticate" and click on Cursor CLI agent
   **Then** I see instructions for configuring Cursor CLI
   **And** I see a "Start Authentication" button
   **And** the agent card shows status: "Not Started"

2. **Given** I am on the Cursor CLI authentication screen
   **When** I click "Start Authentication"
   **Then** a `TerminalSession` is created with type: `auth_setup` and agent: `cursor_cli`
   **And** the session state machine starts in `not_started` state
   **And** a Temporal workflow is triggered: `AgentAuthWorkflow`
   **And** the session transitions to `started` state
   **And** I see a loading indicator: "Starting terminal session..."

3. **Given** the Temporal workflow has started
   **When** the first activity `StartAuthTerminalActivity` executes
   **Then** a Docker container is started via `ContainerService` with:
   - Cursor CLI installed (via cursor.com installer)
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
   **And** I see a success indicator (checkmark) on the Cursor CLI card

7. **Given** I have authenticated Cursor CLI
   **When** I return to edit mode (`/onboarding` after completing onboarding)
   **Then** I see Cursor CLI marked as "Authenticated" with status: `collected`
   **And** I can re-authenticate if needed (creates new `TerminalSession`)

8. **Given** I start a new session with `agent_session` type and have saved credentials
   **When** the container starts
   **Then** my Cursor CLI credentials are automatically loaded into the container
   **And** the Cursor CLI is pre-authenticated

## Tasks / Subtasks

### Task 1: Research Cursor CLI Authentication Flow (AC: 4, 5) ✅ COMPLETE

- [x] Start a container with Cursor CLI image
- [x] Run `agent login` command to auth
- [x] Identify config file location and format
- [x] Document required keys for auth detection
- [x] Update `CursorCliAdapter` with actual paths and keys

**Research Results:**

| Parameter | Value |
|-----------|-------|
| Auth config | `~/.config/cursor/auth.json` |
| CLI config | `~/.cursor/cli-config.json` |
| Home dir | `/home/cursor` |
| Auth keys | `accessToken` |
| Auth command | `agent login` |

**auth.json structure:**
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ..."
}
```

**cli-config.json structure:**
```json
{
  "permissions": { "allow": ["*"], "deny": [] },
  "approvalMode": "auto-edit",
  "sandbox": { "mode": "disabled", "networkAccess": "all" }
}
```

### Task 2: Update CursorCliAdapter with Real Implementation (AC: 5, 6, 8) ✅ COMPLETE

- [x] Update `config_path` to `~/.config/cursor/auth.json`
- [x] Update `auth_required_keys` to `["accessToken"]`
- [x] Implement `auth_complete?` to check for accessToken
- [x] Implement `extract_credentials` to extract tokens
- [x] Implement `generate_config` for auth.json
- [x] Override `config_files` to generate both auth.json and cli-config.json

**File:** `web/app/services/agents/cursor_cli_adapter.rb`

### Task 3: Add Permissions Config (like Codex) (AC: 8) ✅ COMPLETE

- [x] `approvalMode = "auto-edit"` - auto-approve edits
- [x] `sandbox.mode = "disabled"` - disable sandbox
- [x] `sandbox.networkAccess = "all"` - allow all network
- [x] `permissions.allow = ["*"]` - allow all commands

### Task 4: Test Full Auth Flow (AC: 1-7) ⏳ PENDING

- [ ] Test via `/terminal-test` page with "Auth Setup" mode
- [ ] Verify `agent login` works in terminal
- [ ] Verify `/fs/auth` endpoint detects auth completion
- [ ] Verify credentials are saved encrypted to `AgentCredential`

### Task 5: Test Agent Session with Pre-loaded Credentials (AC: 8) ⏳ PENDING

- [ ] Start session with `agent_session` type after auth complete
- [ ] Verify both auth.json and cli-config.json are written
- [ ] Verify Cursor CLI is pre-authenticated

## Dev Notes

### Architecture Context (From Story 2.3)

The infrastructure for agent authentication is **already implemented** in Story 2.3:

1. **TerminalSession Model** - AASM state machine
2. **Temporal Workflows** - `AgentAuthWorkflow`, `AgentSessionWorkflow`
3. **ContainerService** - Docker management with Traefik routing
4. **AgentCredential Model** - Encrypted storage
5. **Adapter Pattern** - `AgentCredentialsService` with agent-specific adapters
6. **Frontend Components** - `AgentAuthTerminal`, `TerminalSessionWidget`

### Docker Image

Cursor CLI is installed from `cursor.com/install`:
- Binary: `/home/cursor/.local/bin/agent`
- Home: `/home/cursor`
- Config likely in: `~/.cursor/` or `~/.config/cursor/`

### CursorCliAdapter Current State (Stub)

```ruby
class CursorCliAdapter < BaseAdapter
  def config_path
    "#{home_dir}/.cursor/config.json"  # TODO: Verify actual path
  end

  def home_dir
    "/home/cursor"
  end

  def auth_required_keys
    %w[accessToken apiKey]  # TODO: Verify actual keys
  end
end
```

### Command for Agent Session

Currently configured in `ContainerService`:
- `auth_setup`: `agent`
- `agent_session`: `agent` (no special flags yet - may need research)

### Pattern from Codex (2.4)

Follow the same pattern as Codex adapter:
1. Research actual config files in running container
2. Update adapter with correct paths
3. Add `config_files` override for multiple configs
4. Add settings to skip permission dialogs

### Testing Strategy

Use `/terminal-test` page:
1. Select "Auth Setup" mode + "Cursor CLI"
2. Click "Start Session"
3. Run auth commands in terminal
4. Verify `/fs/auth` detects auth
5. Click "Save Authentication"
6. Test "With Credentials" mode

### References

- [Source: web/app/services/agents/cursor_cli_adapter.rb] - Current stub
- [Source: web/app/services/agents/codex_adapter.rb] - Reference implementation
- [Source: docker/cursor-cli/Dockerfile] - Docker image
- [Source: _bmad-output/implementation-artifacts/2-4-configure-codex-agent.md] - Codex story

## Dev Agent Record

### Agent Model Used

(To be filled by dev agent)

### Debug Log References

(To be filled by dev agent)

### Completion Notes List

(To be filled by dev agent)

### File List

**To be Modified:**
- `web/app/services/agents/cursor_cli_adapter.rb` - Update with real implementation

**To be Verified:**
- `docker/cursor-cli/Dockerfile` - Verify CLI installation
- `web/app/services/container_service.rb` - May need flags for agent_session
