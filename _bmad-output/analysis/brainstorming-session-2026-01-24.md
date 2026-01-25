---
stepsCompleted: [1]
inputDocuments: ['2-3-configure-claude-code-agent.md']
session_topic: 'Agent Auth Terminal Architecture'
session_goals: 'Design scalable WebSocket proxy + auto-detect auth completion'
selected_approach: 'ai-recommended'
techniques_used: []
ideas_generated: []
context_file: '2-3-configure-claude-code-agent.md'
---

# Brainstorming Session Results

**Facilitator:** Artem_petrov
**Date:** 2026-01-24

## Session Overview

**Topic:** Agent Auth Terminal Architecture - WebSocket Proxy + Auth Detection

**Goals:**
1. Action Cable proxy for WebSocket terminals (scalability)
2. File Watcher for automatically detecting successful authorization
3. Remove direct ports, all traffic through Rails

### Context Guidance

Story 2.3 backend complete. Needed:
- Replace direct `ws://localhost:PORT` connection with Action Cable proxy
- Finish the watcher for the callback on auth success
- Integration between the watcher and the Temporal workflow

---

## Architecture Design

### Current State (Issues)

```
Browser → ws://localhost:7681 → Container ttyd
                ↑
        Direct connection (does not scale)
```

**Issues:**
1. `localhost:PORT` only works locally
2. Many users = many ports (7681-7799)
3. No authorization at the WebSocket level
4. The user manually clicks "Finish Auth"

---

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Browser                                 │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ AgentAuthTerminal│    │ SessionTerminal  │                   │
│  │   (xterm.js)     │    │   (xterm.js)     │                   │
│  └────────┬─────────┘    └────────┬─────────┘                   │
│           │ Action Cable          │ Action Cable                │
└───────────┼───────────────────────┼─────────────────────────────┘
            │                       │
            ▼                       ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Rails (Action Cable)                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    TerminalProxyChannel                      │  │
│  │  - authenticate user via current_user                        │  │
│  │  - lookup TerminalSession → container_id                     │  │
│  │  - proxy WebSocket to container ttyd                         │  │
│  │  - handle reconnection                                       │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                             │                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    AuthCallbackChannel                       │  │
│  │  - receive auth_completed callback from watcher              │  │
│  │  - update TerminalSession state                              │  │
│  │  - signal Temporal workflow                                  │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
└─────────────────────────────┼──────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐    ┌───────────────────────────────────┐
│      Container (ttyd)      │    │      Container (watcher)          │
│  ┌─────────────────────┐  │    │  ┌─────────────────────────────┐  │
│  │   ttyd :7681        │◀─┼────┼──│  Rails connects to ttyd     │  │
│  │   (internal only)   │  │    │  │  via Docker network         │  │
│  └─────────────────────┘  │    │  └─────────────────────────────┘  │
│                           │    │                                   │
│  ┌─────────────────────┐  │    │  ┌─────────────────────────────┐  │
│  │   watcher :4040     │──┼────┼──│  Watch ~/.claude/config     │  │
│  │   (auth detection)  │  │    │  │  HTTP callback to Rails     │  │
│  └─────────────────────┘  │    │  └─────────────────────────────┘  │
└───────────────────────────┘    └───────────────────────────────────┘
```

---

## Component Details

### 1. TerminalProxyChannel (Action Cable)

```ruby
# app/channels/terminal_proxy_channel.rb
class TerminalProxyChannel < ApplicationCable::Channel
  def subscribed
    @session = TerminalSession.find_by(id: params[:session_id])

    reject unless @session && @session.user_id == current_user.id
    reject unless @session.state.in?(%w[running started])

    # Connect to container ttyd via Docker network
    @container_ws = connect_to_container(@session.container_id)

    stream_from "terminal_#{@session.id}"
  end

  def receive(data)
    case data['type']
    when 'input'
      @container_ws.send_input(data['data'])
    when 'resize'
      @container_ws.send_resize(data['cols'], data['rows'])
    end
  end

  private

  def connect_to_container(container_id)
    # Connect via Docker network (container_name:7681)
    # NOT via host port mapping
    container_name = get_container_name(container_id)
    ws_url = "ws://#{container_name}:7681/ws"

    TtydProxyConnection.new(ws_url, self)
  end
end
```

**Key Points:**
- Authorization via `current_user` (Action Cable connection)
- Session owner verification
- Connecting to the container via the Docker network (not via host ports)
- Bidirectional proxy: Browser ↔ Rails ↔ Container

---

### 2. Auth Detection via Watcher

**Option A: HTTP Callback from the Watcher**

```javascript
// docker/base/watcher/index.js - add auth detection

const AUTH_FILES = {
  'claude_code': ['.claude/config', '.claude/credentials.json'],
  'cursor_cli': ['.cursor/credentials'],
  'codex': ['.codex/config'],
  'gemini_cli': ['.gemini/credentials'],
};

// Watch for auth file creation
function watchAuthFiles(agentType, sessionId, callbackUrl) {
  const authPaths = AUTH_FILES[agentType] || [];
  const homeDir = process.env.HOME || '/home/claude';

  authPaths.forEach(relPath => {
    const fullPath = path.join(homeDir, relPath);

    chokidar.watch(fullPath, {
      ignoreInitial: false,
      awaitWriteFinish: true
    }).on('add', async (filePath) => {
      log.info(`Auth file detected: ${filePath}`);

      // Validate file has content
      const content = fs.readFileSync(filePath, 'utf-8');
      if (content.length > 0) {
        // Callback to Rails
        await fetch(callbackUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            session_id: sessionId,
            agent_type: agentType,
            auth_detected: true,
            file_path: relPath,
          })
        });
      }
    });
  });
}
```

**Option B: Polling from Rails (simpler, but more latency)**

```ruby
# Temporal activity polls for auth file
loop do
  files = ContainerService.extract_files(container_id, auth_paths)
  if files.values.any?(&:present?)
    break # Auth detected
  end
  sleep 5
end
```

**Recommendation:** Option A (HTTP callback) - less latency, cleaner.

---

### 3. Container Network Configuration

**Changes in ContainerService:**

```ruby
# app/services/container_service.rb

def start_auth_container(user_id, agent_type)
  # ...

  container = Docker::Container.create(
    "name" => container_name,
    "Image" => image,
    "Env" => [
      "USER_ID=#{user_id}",
      "AGENT_TYPE=#{agent_type}",
      "SESSION_ID=#{session_id}",           # NEW
      "AUTH_CALLBACK_URL=#{callback_url}",  # NEW
      # ...
    ],
    # Do NOT expose ports externally!
    # "PortBindings" => { ... } - REMOVE
    "HostConfig" => {
      "NetworkMode" => "palad_default",  # Docker Compose network
      # ...
    }
  )

  {
    container_id: container.id[0..11],
    container_name: container_name,  # For connecting via the Docker network
    # remove websocket_url - now via Action Cable
  }
end
```

**Docker Compose network:**
```yaml
services:
  web:
    networks:
      - palad_default

  # Agent containers are also on this network
  # (created dynamically via the Docker API)

networks:
  palad_default:
    driver: bridge
```

---

### 4. Updated Flow

```
1. User clicks "Start Authentication"
   └─> POST /api/v1/terminal_sessions
       └─> TerminalSession.create(state: :not_started)
       └─> Transition to :started → Temporal workflow

2. Temporal: StartAuthTerminalActivity
   └─> ContainerService.start_auth_container
       └─> Container starts in Docker network
       └─> Container runs ttyd + watcher
       └─> NO host port mapping
   └─> Update TerminalSession with container_name
   └─> Transition to :running

3. Frontend connects via Action Cable
   └─> TerminalProxyChannel.subscribed
       └─> Verify user owns session
       └─> Connect to ws://container_name:7681/ws
       └─> Proxy bidirectional

4. User authenticates in terminal
   └─> claude login → creates ~/.claude/config

5. Watcher detects auth file
   └─> HTTP POST to Rails auth callback endpoint
       └─> POST /api/v1/terminal_sessions/:id/auth_detected

6. Rails receives callback
   └─> TerminalSession.transition to :finished
   └─> Signal Temporal workflow: authentication_finished
   └─> Frontend receives state update via polling/push

7. Temporal continues
   └─> CollectArtifactsActivity
       └─> Extract ~/.claude/config from container
       └─> Save to AgentCredential
   └─> StopContainerActivity
       └─> Stop and remove container
   └─> TerminalSession → :collected
```

---

## Implementation Tasks

### Phase 1: Traefik Setup ✅ DONE (replaced AnyCable)

**Architecture:** Rails = Control Plane, Traefik = Data Plane

- [x] Remove AnyCable (gem, config, docker service)
- [x] Add Traefik to docker-compose.yml
- [x] Configure ForwardAuth middleware
- [x] Create `Api::Internal::WsAuthController` for ForwardAuth
- [x] Update `ContainerService` with Traefik labels
- [x] Route `/s/{id}/tty` → container:7681 (ttyd)
- [x] Route `/s/{id}/fs` → container:4040 (watcher)
- [x] Revert to standard Action Cable (for UI notifications only)

### Phase 2: Terminal Session Token ✅ DONE

- [x] Add `websocket_token` column to terminal_sessions
- [x] Generate token on session creation
- [x] Pass token to container via WEBSOCKET_TOKEN env var
- [x] Token used for auth_callback verification

### Phase 3: Auth Callback ✅ DONE

- [x] Create `Api::Internal::AuthCallbackController`
- [x] Add route `POST /api/internal/auth_callback`
- [x] Verify callback using WEBSOCKET_TOKEN
- [x] Update TerminalSession state on auth detected
- [ ] Update watcher to detect auth files and call callback
- [ ] Signal Temporal workflow

### Phase 4: Cleanup Workflow

- [ ] Create `ContainerCleanupWorkflow`
- [ ] Create `FindStaleSessionsActivity`
- [ ] Add schedule to schedules.yml (every 5 min)
- [ ] Test cleanup logic

---

## Decisions Made

| Question | Decision |
|--------|---------|
| 1. Architecture | Rails = Control Plane, Traefik = Data Plane |
| 2. WebSocket proxy | Traefik with ForwardAuth (not AnyCable) |
| 3. Action Cable | Only for UI statuses, not for terminal data |
| 4. Auth | Traefik ForwardAuth → Rails → verify session ownership |
| 5. Cleanup | Scheduled Temporal workflow (every 5 min) |

---

## Final Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Browser                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              xterm.js + @rails/actioncable                │   │
│  └────────────────────────┬─────────────────────────────────┘   │
└───────────────────────────┼─────────────────────────────────────┘
                            │ wss://app/cable
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                    AnyCable (Go WebSocket Server)                  │
│                         Port 8085                                  │
└───────────────────────────┬───────────────────────────────────────┘
                            │ gRPC
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Rails (anycable-rails)                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  TerminalProxyChannel                        │  │
│  │  - Auth via current_user                                     │  │
│  │  - Lookup session → container WebSocket URL                  │  │
│  │  - Proxy to container via internal WebSocket                 │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              AuthCallbackController                          │  │
│  │  POST /api/internal/auth_callback                            │  │
│  │  - Receive callback from watcher                             │  │
│  │  - Update TerminalSession → :finished                        │  │
│  │  - Signal Temporal workflow                                  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                      Docker Container                              │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐  │
│  │   ttyd :7681    │    │   watcher :4040                     │  │
│  │   (terminal)    │    │   - Watch ~/.claude/config          │  │
│  └─────────────────┘    │   - HTTP POST to Rails on detect    │  │
│                         └─────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────┐
│                    Temporal (Scheduled)                            │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │              ContainerCleanupWorkflow                        │  │
│  │  - Runs every 5 minutes                                      │  │
│  │  - Find sessions running > 30 min                            │  │
│  │  - Stop containers, mark sessions as failed                  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

---

## Implementation Tasks

### Phase 1: AnyCable Setup ✅ DONE

- [x] Add `anycable-rails` gem to Gemfile
- [x] Add `anycable-go` service to docker-compose.yml
- [x] Create config/anycable.yml
- [x] Update config/cable.yml for any_cable adapter
- [x] Add ANYCABLE env vars to web service
- [x] Add anycable to Procfile.dev
- [x] Add action_cable_meta_tag to layout
- [x] Configure action_cable.url in development.rb
- [x] Update connection.rb with current_user identification
- [x] Create TerminalProxyChannel (basic structure)
- [x] Run `bundle install` to install gem
- [x] Test basic setup - AnyCable-Go + RPC working
- [x] Verify meta tag renders correct URL

### Phase 2: Terminal Proxy Channel

- [ ] Create `TerminalProxyChannel`
- [ ] Implement WebSocket proxy to container (async-websocket or similar)
- [ ] Handle bidirectional message passing
- [ ] Update frontend to use channel instead of direct WebSocket

### Phase 3: Auth Detection Watcher

- [ ] Update watcher to detect auth files per agent type
- [ ] Add HTTP callback on file detection
- [ ] Create `POST /api/internal/auth_callback` endpoint
- [ ] Update TerminalSession state on callback
- [ ] Signal Temporal workflow

### Phase 4: Cleanup Workflow

- [ ] Create `ContainerCleanupWorkflow`
- [ ] Create `FindStaleSessionsActivity`
- [ ] Create `FailSessionActivity`
- [ ] Add schedule to `schedules.yml` (every 5 min)
- [ ] Test cleanup logic

### Phase 5: Frontend Updates

- [ ] Update `AgentAuthTerminal` to use Action Cable
- [ ] Add exponential backoff reconnect
- [ ] Remove "Finish Authentication" button (auto-detect)
- [ ] Show "Authentication detected!" message

---

## Files to Create/Modify

### New Files:
- `web/app/channels/terminal_proxy_channel.rb`
- `web/app/controllers/api/internal/auth_callbacks_controller.rb`
- `web/app/temporal/workflows/container_cleanup_workflow.rb`
- `web/app/temporal/activities/find_stale_sessions_activity.rb`
- `web/app/temporal/activities/fail_session_activity.rb`

### Modified Files:
- `docker-compose.yml` - add anycable-go service
- `web/Gemfile` - add anycable-rails
- `web/config/cable.yml` - anycable adapter
- `web/config/anycable.yml` - anycable config
- `web/config/routes.rb` - internal callback route
- `docker/base/watcher/index.js` - auth detection
- `web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx` - use channel
- `web/app/temporal/schedules.yml` - cleanup schedule

---

## AnyCable Configuration

### docker-compose.yml addition:
```yaml
anycable:
  image: anycable/anycable-go:1.5
  ports:
    - "8085:8085"
  environment:
    ANYCABLE_HOST: "0.0.0.0"
    ANYCABLE_PORT: 8085
    ANYCABLE_REDIS_URL: redis://redis:6379/0
    ANYCABLE_RPC_HOST: web:50051
    ANYCABLE_DEBUG: "true"
  depends_on:
    - redis
    - web

web:
  environment:
    ANYCABLE_RPC_HOST: "0.0.0.0:50051"
```

### Gemfile:
```ruby
gem "anycable-rails", "~> 1.5"
gem "grpc", "~> 1.60"  # for anycable RPC
```

### config/cable.yml:
```yaml
development:
  adapter: any_cable

production:
  adapter: any_cable
```

---

## Watcher Auth Detection

### Auth file paths per agent:
```javascript
const AUTH_FILES = {
  claude_code: ['.claude/settings.json', '.claude.json'],
  cursor_cli: ['.cursor/settings.json'],
  codex: ['.codex/config.json'],
  gemini_cli: ['.config/gemini/credentials.json'],
};
```

### Callback payload:
```json
{
  "session_id": 123,
  "agent_type": "claude_code",
  "detected_file": ".claude/settings.json",
  "timestamp": "2026-01-24T12:00:00Z"
}
```

---

## Cleanup Workflow Schedule

```yaml
# web/app/temporal/schedules.yml
schedules:
  container_cleanup:
    workflow: Workflows::ContainerCleanupWorkflow
    cron: "*/5 * * * *"
    args:
      max_age_minutes: 30
```
