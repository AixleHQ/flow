# Technical Design: xterm.js + Docker + Claude Code

**Date:** 2026-01-16
**Author:** Artem Petrov
**Status:** Ready for Implementation
**Related:** [interactive-agent-architecture-v2-claude-code-2026-01-16.md](./interactive-agent-architecture-v2-claude-code-2026-01-16.md)

---

## 🎯 Goal

Implement an interactive in-browser terminal connected to a Docker container with the Claude Code CLI.

---

## 📋 Tasks Breakdown

### Task 1: xterm.js component with React

**Goal:** Create a reusable terminal component.

**Files:**
- `web/app/frontend/shared/ui/Terminal/Terminal.tsx`
- `web/app/frontend/shared/ui/Terminal/index.ts`
- `web/app/frontend/shared/ui/Terminal/useTerminal.ts`

**Dependencies:**
```bash
cd web && yarn add xterm @xterm/xterm @xterm/addon-fit @xterm/addon-web-links
```

**Component:**

```tsx
// web/app/frontend/shared/ui/Terminal/Terminal.tsx

import { useEffect, useRef, useCallback } from 'react';
import { Terminal as XTerm } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import '@xterm/xterm/css/xterm.css';

interface TerminalProps {
  onData?: (data: string) => void;  // User input
  onResize?: (cols: number, rows: number) => void;
  fontSize?: number;
  className?: string;
}

export function Terminal({
  onData,
  onResize,
  fontSize = 14,
  className
}: TerminalProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const terminalRef = useRef<XTerm | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);

  // Initialize terminal
  useEffect(() => {
    if (!containerRef.current) return;

    const terminal = new XTerm({
      fontSize,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: '#1e1e1e',
        foreground: '#d4d4d4',
        cursor: '#d4d4d4',
        cursorAccent: '#1e1e1e',
        selectionBackground: '#264f78',
      },
      cursorBlink: true,
      cursorStyle: 'block',
      scrollback: 10000,
      convertEol: true,
    });

    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();

    terminal.loadAddon(fitAddon);
    terminal.loadAddon(webLinksAddon);

    terminal.open(containerRef.current);
    fitAddon.fit();

    terminalRef.current = terminal;
    fitAddonRef.current = fitAddon;

    // Handle user input
    if (onData) {
      terminal.onData(onData);
    }

    // Handle resize
    const resizeObserver = new ResizeObserver(() => {
      fitAddon.fit();
      if (onResize) {
        onResize(terminal.cols, terminal.rows);
      }
    });
    resizeObserver.observe(containerRef.current);

    return () => {
      resizeObserver.disconnect();
      terminal.dispose();
    };
  }, [fontSize, onData, onResize]);

  // Expose write method via ref or callback
  const write = useCallback((data: string) => {
    terminalRef.current?.write(data);
  }, []);

  const clear = useCallback(() => {
    terminalRef.current?.clear();
  }, []);

  return (
    <div
      ref={containerRef}
      className={className}
      style={{
        width: '100%',
        height: '100%',
        backgroundColor: '#1e1e1e',
      }}
    />
  );
}

// Export imperative handle type
export interface TerminalHandle {
  write: (data: string) => void;
  clear: () => void;
}
```

```tsx
// web/app/frontend/shared/ui/Terminal/useTerminal.ts

import { useRef, useCallback } from 'react';
import { Terminal as XTerm } from '@xterm/xterm';

export function useTerminal() {
  const terminalRef = useRef<XTerm | null>(null);

  const write = useCallback((data: string) => {
    terminalRef.current?.write(data);
  }, []);

  const writeln = useCallback((data: string) => {
    terminalRef.current?.writeln(data);
  }, []);

  const clear = useCallback(() => {
    terminalRef.current?.clear();
  }, []);

  const focus = useCallback(() => {
    terminalRef.current?.focus();
  }, []);

  return {
    terminalRef,
    write,
    writeln,
    clear,
    focus,
  };
}
```

```ts
// web/app/frontend/shared/ui/Terminal/index.ts

export { Terminal } from './Terminal';
export { useTerminal } from './useTerminal';
export type { TerminalHandle } from './Terminal';
```

**Acceptance Criteria:**
- [ ] Terminal renders in the DOM
- [ ] User can type text
- [ ] Terminal automatically adapts to the container size
- [ ] Clickable links work

---

### Task 2: Docker socket + Container management in Rails

**Goal:** Learn to create and manage containers from Rails.

**Dependencies:**
```ruby
# web/Gemfile
gem 'docker-api', '~> 2.3'
```

**Docker socket mount:**
```yaml
# docker-compose.yml — add to the web service

services:
  web:
    # ... existing config
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # ADD THIS
```

**Service:**

```ruby
# web/app/services/container_manager.rb

require 'docker'

class ContainerManager
  AGENT_IMAGE = 'palad-claude-session:latest'

  class << self
    def create_session(session_id:, step_name:, repo_url: nil, mounted_artifacts: [])
      container_name = "palad-#{session_id}-#{step_name}"

      # Prepare volumes
      volumes = build_volumes(session_id, step_name, mounted_artifacts)

      # Prepare environment
      env = build_environment(session_id, step_name, repo_url)

      # Create container
      container = Docker::Container.create(
        'name' => container_name,
        'Image' => AGENT_IMAGE,
        'Tty' => true,
        'OpenStdin' => true,
        'Env' => env,
        'HostConfig' => {
          'Binds' => volumes,
          'Memory' => 2 * 1024 * 1024 * 1024, # 2GB
          'CpuPeriod' => 100_000,
          'CpuQuota' => 100_000, # 1 CPU
        }
      )

      container.start

      # Store container ID in Redis for WebSocket lookup
      Redis.current.set("palad:#{session_id}:#{step_name}:container", container.id)

      container
    end

    def stop_session(session_id:, step_name:)
      container_id = Redis.current.get("palad:#{session_id}:#{step_name}:container")
      return unless container_id

      begin
        container = Docker::Container.get(container_id)
        container.stop(timeout: 10)
        container.remove
      rescue Docker::Error::NotFoundError
        # Container already removed
      end

      Redis.current.del("palad:#{session_id}:#{step_name}:container")
    end

    def get_container(session_id:, step_name:)
      container_id = Redis.current.get("palad:#{session_id}:#{step_name}:container")
      return nil unless container_id

      begin
        Docker::Container.get(container_id)
      rescue Docker::Error::NotFoundError
        nil
      end
    end

    def container_running?(session_id:, step_name:)
      container = get_container(session_id: session_id, step_name: step_name)
      return false unless container

      container.info['State']['Running']
    end

    private

    def build_volumes(session_id, step_name, mounted_artifacts)
      workspace_root = Rails.root.join('tmp', 'workspaces', session_id)
      FileUtils.mkdir_p(workspace_root.join('output'))

      volumes = [
        "#{workspace_root.join('output')}:/workspace/output:rw",
      ]

      # Mount repo if exists
      repo_path = workspace_root.join('repo')
      if repo_path.exist?
        volumes << "#{repo_path}:/workspace/repo:ro"
      end

      # Mount previous step artifacts
      mounted_artifacts.each_with_index do |artifact_path, index|
        volumes << "#{artifact_path}:/workspace/context/step-#{index + 1}:ro"
      end

      volumes
    end

    def build_environment(session_id, step_name, repo_url)
      env = [
        "SESSION_ID=#{session_id}",
        "STEP_NAME=#{step_name}",
        "ANTHROPIC_API_KEY=#{ENV.fetch('ANTHROPIC_API_KEY')}",
        "MODEL=#{ENV.fetch('CLAUDE_MODEL', 'claude-sonnet-4-20250514')}",
      ]

      env << "REPO_URL=#{repo_url}" if repo_url.present?

      env
    end
  end
end
```

**API Controller:**

```ruby
# web/app/controllers/api/v1/sessions_controller.rb

module Api
  module V1
    class SessionsController < ApplicationController
      def create
        session = Session.create!(
          workflow_run_id: params[:workflow_run_id],
          step_name: params[:step_name],
          status: 'starting'
        )

        # Start container in background
        ContainerStartJob.perform_later(session.id)

        render json: { session_id: session.id }, status: :created
      end

      def show
        session = Session.find(params[:id])
        container_running = ContainerManager.container_running?(
          session_id: session.id.to_s,
          step_name: session.step_name
        )

        render json: {
          id: session.id,
          step_name: session.step_name,
          status: session.status,
          container_running: container_running,
        }
      end

      def destroy
        session = Session.find(params[:id])

        ContainerManager.stop_session(
          session_id: session.id.to_s,
          step_name: session.step_name
        )

        session.update!(status: 'stopped')

        render json: { status: 'stopped' }
      end
    end
  end
end
```

**Acceptance Criteria:**
- [ ] Docker socket is accessible from the Rails container
- [ ] `ContainerManager.create_session` creates a container
- [ ] `ContainerManager.stop_session` stops and removes the container
- [ ] Container ID is stored in Redis

---

### Task 3: WebSocket connection of xterm to the Docker PTY

**Goal:** Connect the browser terminal to the container's stdin/stdout.

**ActionCable Channel:**

```ruby
# web/app/channels/terminal_channel.rb

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @session_id = params[:session_id]
    @step_name = params[:step_name]

    # Get container
    container_id = Redis.current.get("palad:#{@session_id}:#{@step_name}:container")
    unless container_id
      reject
      return
    end

    @container = Docker::Container.get(container_id)

    # Attach to container with PTY
    @connection = @container.attach(
      stream: true,
      stdin: true,
      stdout: true,
      stderr: true,
      tty: true,
      logs: false
    )

    # Start reader thread for container output
    @reader_thread = Thread.new do
      begin
        @connection[1].each do |chunk|
          transmit({ type: 'output', data: chunk })
        end
      rescue IOError, Errno::EBADF
        # Connection closed
      end
    end

    stream_from "terminal:#{@session_id}:#{@step_name}"
  end

  def receive(data)
    case data['type']
    when 'input'
      # Forward user input to container stdin
      @connection[0].write(data['data'])
    when 'resize'
      # Resize PTY (if supported)
      @container.exec(['stty', 'rows', data['rows'].to_s, 'cols', data['cols'].to_s])
    end
  rescue IOError, Errno::EPIPE
    # Container stdin closed
    transmit({ type: 'disconnect', reason: 'Container stdin closed' })
  end

  def unsubscribed
    @reader_thread&.kill
    @connection&.first&.close rescue nil
  end
end
```

**Frontend Hook:**

```tsx
// web/app/frontend/shared/lib/hooks/useTerminalWebSocket.ts

import { useEffect, useRef, useCallback, useState } from 'react';
import { createConsumer } from '@rails/actioncable';

interface UseTerminalWebSocketOptions {
  sessionId: string;
  stepName: string;
  onOutput: (data: string) => void;
  onDisconnect?: (reason: string) => void;
}

export function useTerminalWebSocket({
  sessionId,
  stepName,
  onOutput,
  onDisconnect,
}: UseTerminalWebSocketOptions) {
  const subscriptionRef = useRef<ActionCable.Subscription | null>(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    const consumer = createConsumer();

    const subscription = consumer.subscriptions.create(
      {
        channel: 'TerminalChannel',
        session_id: sessionId,
        step_name: stepName,
      },
      {
        connected() {
          setConnected(true);
        },
        disconnected() {
          setConnected(false);
          onDisconnect?.('WebSocket disconnected');
        },
        rejected() {
          setConnected(false);
          onDisconnect?.('Connection rejected');
        },
        received(data: { type: string; data?: string; reason?: string }) {
          if (data.type === 'output' && data.data) {
            onOutput(data.data);
          } else if (data.type === 'disconnect') {
            onDisconnect?.(data.reason || 'Unknown');
          }
        },
      }
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
    };
  }, [sessionId, stepName, onOutput, onDisconnect]);

  const sendInput = useCallback((data: string) => {
    subscriptionRef.current?.perform('receive', { type: 'input', data });
  }, []);

  const sendResize = useCallback((cols: number, rows: number) => {
    subscriptionRef.current?.perform('receive', { type: 'resize', cols, rows });
  }, []);

  return {
    connected,
    sendInput,
    sendResize,
  };
}
```

**Integrated Terminal Page:**

```tsx
// web/app/frontend/pages/session/ui/SessionTerminal.tsx

import { useCallback } from 'react';
import { Terminal } from '@/shared/ui/Terminal';
import { useTerminalWebSocket } from '@/shared/lib/hooks/useTerminalWebSocket';
import { useTerminal } from '@/shared/ui/Terminal';

interface SessionTerminalProps {
  sessionId: string;
  stepName: string;
}

export function SessionTerminal({ sessionId, stepName }: SessionTerminalProps) {
  const { terminalRef, write } = useTerminal();

  const handleOutput = useCallback((data: string) => {
    write(data);
  }, [write]);

  const handleDisconnect = useCallback((reason: string) => {
    write(`\r\n\x1b[31m[Disconnected: ${reason}]\x1b[0m\r\n`);
  }, [write]);

  const { connected, sendInput, sendResize } = useTerminalWebSocket({
    sessionId,
    stepName,
    onOutput: handleOutput,
    onDisconnect: handleDisconnect,
  });

  return (
    <div className="h-full flex flex-col">
      <div className="bg-gray-800 px-4 py-2 flex items-center gap-2">
        <div
          className={`w-3 h-3 rounded-full ${connected ? 'bg-green-500' : 'bg-red-500'}`}
        />
        <span className="text-white text-sm">
          {stepName} {connected ? '(connected)' : '(disconnected)'}
        </span>
      </div>
      <div className="flex-1">
        <Terminal
          ref={terminalRef}
          onData={sendInput}
          onResize={sendResize}
        />
      </div>
    </div>
  );
}
```

**Acceptance Criteria:**
- [ ] WebSocket connection is established
- [ ] User input is forwarded to the container
- [ ] Container output is displayed in the terminal
- [ ] Terminal resize works

---

### Task 4: Docker image with the Claude Code CLI

**Goal:** Create an image with Claude Code installed.

**Files:**
- `docker/claude-session/Dockerfile`
- `docker/claude-session/entrypoint.sh`
- `docker/claude-session/prompts/` (BMAD prompts)

**Dockerfile:**

```dockerfile
# docker/claude-session/Dockerfile

FROM node:20-slim

# System tools for code analysis
RUN apt-get update && apt-get install -y \
    git \
    ripgrep \
    fd-find \
    jq \
    curl \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create workspace structure
RUN mkdir -p /workspace/repo /workspace/context /workspace/output

# Copy entrypoint and prompts
COPY entrypoint.sh /app/
COPY prompts/ /prompts/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/app/entrypoint.sh"]
```

**Entrypoint:**

```bash
#!/bin/bash
# docker/claude-session/entrypoint.sh

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  PALAD Session: ${STEP_NAME:-unknown}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Clone repo if URL provided
if [ -n "$REPO_URL" ]; then
    echo "📦 Cloning repository..."
    git clone --depth 1 "$REPO_URL" /workspace/repo 2>/dev/null || {
        echo "⚠️  Failed to clone repo: $REPO_URL"
    }
fi

# Create output directory
mkdir -p /workspace/output

# Setup Claude Code config directory
mkdir -p /workspace/.claude

# Create settings.json with permissions
cat > /workspace/.claude/settings.json << EOF
{
  "model": "${MODEL:-claude-sonnet-4-20250514}",
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(git:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(tree:*)",
      "Bash(rg:*)",
      "Edit(/workspace/output/**)",
      "Write(/workspace/output/**)"
    ],
    "deny": [
      "Bash(rm:*)",
      "Bash(mv:*)",
      "Edit(/workspace/repo/**)",
      "Write(/workspace/repo/**)"
    ],
    "defaultMode": "acceptEdits"
  }
}
EOF

# Copy step-specific CLAUDE.md prompt
if [ -n "$STEP_NAME" ] && [ -f "/prompts/${STEP_NAME}.md" ]; then
    cp "/prompts/${STEP_NAME}.md" /workspace/CLAUDE.md
    echo "✅ Loaded BMAD prompt for: ${STEP_NAME}"
else
    echo "ℹ️  No specific prompt for step: ${STEP_NAME:-none}"
fi

# Show workspace info
echo ""
echo "  Workspace:"
echo "    repo:    /workspace/repo"
echo "    context: /workspace/context"
echo "    output:  /workspace/output"
echo ""
echo "  Commands:"
echo "    claude   - Start AI assistant"
echo "    exit     - Finish this step"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Start interactive shell
exec bash
```

**Build command (add to the Makefile):**

```makefile
# Makefile

build-claude-session:
	docker build -t palad-claude-session:latest -f docker/claude-session/Dockerfile docker/claude-session/
```

**Acceptance Criteria:**
- [ ] Image builds without errors
- [ ] Claude Code CLI is available (`claude --version`)
- [ ] CLAUDE.md is copied from prompts/
- [ ] settings.json is created with the correct permissions

---

### Task 5: ANTHROPIC_API_KEY in the environment

**Goal:** Securely pass the API key into the container.

**Update docker-compose.yml:**

```yaml
# docker-compose.yml — add to x-web-environment

x-web-environment: &web-environment
  # ... existing vars
  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}  # ADD THIS
  CLAUDE_MODEL: ${CLAUDE_MODEL:-claude-sonnet-4-20250514}
```

**Create .env.example:**

```bash
# .env.example

# Anthropic API
ANTHROPIC_API_KEY=sk-ant-xxx
CLAUDE_MODEL=claude-sonnet-4-20250514
```

**Update .gitignore:**

```gitignore
# .gitignore
.env
.env.local
```

**Check in ContainerManager:**

```ruby
# web/app/services/container_manager.rb

def build_environment(session_id, step_name, repo_url)
  api_key = ENV.fetch('ANTHROPIC_API_KEY') do
    raise "ANTHROPIC_API_KEY environment variable is not set"
  end

  env = [
    "SESSION_ID=#{session_id}",
    "STEP_NAME=#{step_name}",
    "ANTHROPIC_API_KEY=#{api_key}",
    "MODEL=#{ENV.fetch('CLAUDE_MODEL', 'claude-sonnet-4-20250514')}",
  ]

  env << "REPO_URL=#{repo_url}" if repo_url.present?

  env
end
```

**Acceptance Criteria:**
- [ ] `.env` file is not in git
- [ ] `.env.example` contains a template
- [ ] Rails reads ANTHROPIC_API_KEY from ENV
- [ ] Container receives the API key through the environment

---

## 📊 Implementation Order

```
Task 1: xterm.js component
    │
    └── Standalone, no dependencies

Task 2: Docker socket + ContainerManager
    │
    ├── Depends on: docker-compose.yml changes
    └── Depends on: docker-api gem

Task 3: WebSocket connection
    │
    ├── Depends on: Task 1 (Terminal component)
    └── Depends on: Task 2 (Container running)

Task 4: Claude Code Docker image
    │
    └── Standalone, can be done in parallel

Task 5: API Key management
    │
    └── Depends on: Task 2 (ContainerManager uses it)
```

**Recommended order:** 1 → 4 → 5 → 2 → 3

---

## ✅ Definition of Done

All tasks are considered complete when:

1. User opens the session page
2. A Docker container with Claude Code is created
3. xterm.js connects to the container over WebSocket
4. User sees a greeting and can run `claude`
5. Claude Code works interactively
6. On `exit` the container stops

---

## 🔗 References

- [xterm.js Documentation](https://xtermjs.org/)
- [docker-api gem](https://github.com/swipely/docker-api)
- [ActionCable Guide](https://guides.rubyonrails.org/action_cable_overview.html)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
