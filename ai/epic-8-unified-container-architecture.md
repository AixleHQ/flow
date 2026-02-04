# Epic 8: Unified Container Execution Architecture

## Overview

Unified container execution framework using Strategy Pattern with lifecycle hooks, supporting:
- Agent authentication containers
- Agent session containers
- Tool execution containers
- Future: any container-based workload

## Core Principles

1. **Single Execution Entry Point**: `ContainerExecutionService.execute(strategy:, input:)`
2. **Strategy Pattern**: Each use case = separate strategy class
3. **Lifecycle Hooks**: 8 phases with individual timeouts
4. **Timeout Protection**: Per-phase and global timeouts to prevent abuse
5. **Artifact Collection**: Standardized before_cleanup phase

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                  UnifiedContainerWorkflow                       │
│                   (Temporal Workflow)                           │
│                                                                 │
│  Input: { strategy_type, strategy_input, image, timeouts }     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────┐
         │  PullDockerImageActivity      │
         │  Timeout: 5-10 minutes        │
         │                               │
         │  → docker pull {image}        │
         │  → Idempotent (fast if cached)│
         │  → Required for all strategies│
         └───────────┬───────────────────┘
                     │
                     ▼
         ┌───────────────────────────────┐
         │  ExecuteContainerActivity     │
         │                               │
         │  → Resolve Strategy Class     │
         │  → Call ContainerExecution    │
         └───────────┬───────────────────┘
                     │
                     ▼
    ┌────────────────────────────────────────┐
    │   ContainerExecutionService            │
    │   (Unified Orchestrator)               │
    │                                        │
    │   Lifecycle Phases (with timeouts):    │
    │   1. before_create   (30s)             │
    │   2. create          (60s)             │
    │   3. before_start    (30s)             │
    │   4. start           (60s)             │
    │   5. before_exec     (120s)            │
    │   6. exec            (strategy-based)  │
    │   7. before_cleanup  (120s)            │
    │   8. cleanup         (30s)             │
    └────────┬───────────────────────────────┘
             │
             ▼
    ┌────────────────────────────────────────┐
    │         Strategy Classes               │
    │  (implements lifecycle hooks)          │
    │                                        │
    │  ┌──────────────────────────┐          │
    │  │  AgentAuthStrategy       │          │
    │  │  - exec: wait for signal │          │
    │  │  - timeout: infinite     │          │
    │  │  - before_cleanup:       │          │
    │  │    collect auth files    │          │
    │  └──────────────────────────┘          │
    │                                        │
    │  ┌──────────────────────────┐          │
    │  │  AgentSessionStrategy    │          │
    │  │  - before_exec: load     │          │
    │  │    credentials           │          │
    │  │  - exec: wait for signal │          │
    │  │  - before_cleanup:       │          │
    │  │    collect logs/artifacts│          │
    │  └──────────────────────────┘          │
    │                                        │
    │  ┌──────────────────────────┐          │
    │  │  ToolExecutionStrategy   │          │
    │  │  - before_exec: inject   │          │
    │  │    tool files            │          │
    │  │  - exec: run command     │          │
    │  │  - timeout: 5-30 min     │          │
    │  │  - before_cleanup: collect│          │
    │  │    output artifacts       │          │
    │  └──────────────────────────┘          │
    └────────────────────────────────────────┘
```

---

## Lifecycle Phases with Timeouts

```
Activity/Phase      | Default Timeout | Description                          | Responsibility
--------------------|-----------------|--------------------------------------|------------------
PullDockerImage     | 600s (10min)   | Pull Docker image from registry      | Activity
before_create       | 30s            | Validate input, resolve config       | Strategy
create              | 60s            | Docker container create API call     | Base/Strategy
before_start        | 30s            | Configure labels, network, volumes   | Strategy
start               | 60s            | Docker container start + health check| Base
before_exec         | 120s           | Inject files/credentials into container| Strategy
exec                | Variable       | Main execution (command/wait/signal) | Strategy
before_cleanup      | 120s           | Collect artifacts, logs, auth files  | Strategy
cleanup             | 30s            | Stop and remove container            | Base

Total Max Timeout (tool): ~42 minutes (10min pull + 30min exec + 2min overhead)
Total Max Timeout (agent): ~11 minutes + infinite exec (10min pull + wait for user)

Note: Pull is idempotent - if image exists locally, completes in <1s
```

### Timeout Configuration

```ruby
# config/settings.yml
container_execution:
  timeouts:
    pull_image: 600        # seconds (10 min) - for large custom tool images
    before_create: 30      # seconds
    create: 60             # seconds
    before_start: 30       # seconds
    start: 60              # seconds
    before_exec: 120       # seconds
    exec_default: 300      # seconds (5 min) - for tools
    exec_max: 1800         # seconds (30 min) - for tools
    before_cleanup: 120    # seconds
    cleanup: 30            # seconds

  limits:
    tool_execution:
      memory_mb: 512       # Max memory per tool container
      cpu_percent: 50      # Max CPU (50% of 1 core)
      max_timeout: 1800    # Absolute max for tool exec (30 min)
```

---

## Pull Image Activity (Before Execution)

### Why Separate Activity?

**Benefits:**
1. **Idempotent** - Fast if image already cached locally (< 1s)
2. **Long timeout** - Custom tool images can be large (10 min max)
3. **Retry logic** - Can retry pull failures without re-executing workflow
4. **Visibility** - User sees "Pulling image..." progress in UI
5. **Shared** - Same image pulled once for multiple executions

### PullDockerImageActivity Implementation

```ruby
# app/temporal/activities/pull_docker_image_activity.rb
module Activities
  class PullDockerImageActivity < Base
    # Timeout: 10 minutes for large images
    activity_timeout 600

    def run(input)
      image = input.image || input["image"]
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[PullImage] Checking image: #{image}")

      # Check if image exists locally
      begin
        Docker::Image.get(image)
        Rails.logger.info("[PullImage] Image already cached: #{image}")
        return { status: :cached, image: image }
      rescue Docker::Error::NotFoundError
        Rails.logger.info("[PullImage] Image not found locally, pulling: #{image}")
      end

      # Pull image with progress logging
      start_time = Time.current
      Docker::Image.create("fromImage" => image) do |chunk|
        # Parse progress JSON from Docker API
        progress = parse_pull_progress(chunk)
        Rails.logger.info("[PullImage] #{progress}") if progress
      end

      duration = (Time.current - start_time).to_i
      Rails.logger.info("[PullImage] Pull completed: #{image} (#{duration}s)")

      { status: :pulled, image: image, duration_seconds: duration }
    rescue Docker::Error::DockerError => e
      Rails.logger.error("[PullImage] Docker error: #{e.message}")
      raise ActivityError, "Failed to pull image #{image}: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("[PullImage] Error pulling image: #{e.message}")
      raise ActivityError, "Failed to pull image #{image}: #{e.message}"
    end

    private

    def parse_pull_progress(chunk)
      data = JSON.parse(chunk)
      if data["status"]
        status = data["status"]
        progress = data["progress"] || ""
        id = data["id"] || ""
        "#{id} #{status} #{progress}".strip
      end
    rescue JSON::ParserError
      nil
    end
  end
end
```

### Workflow Integration

```ruby
# app/temporal/workflows/unified_container_workflow.rb
module Workflows
  class UnifiedContainerWorkflow < Base
    workflow_signal
    def container_finished
      @finished = true
    end

    def run(input)
      strategy_type = input.strategy_type
      image = input.image || input.strategy_input&.image
      @finished = false

      # Step 1: ALWAYS pull image first (fast if cached, required for execution)
      Rails.logger.info("[Workflow] Pulling image: #{image}")
      pull_result = execute_activity(
        WorkflowService.unified_workflow.activities.pull_docker_image_activity,
        { image: image },
        timeout: 600 # 10 minutes
      )
      Rails.logger.info("[Workflow] Image ready: #{pull_result[:status]}")

      # Step 2: Execute container strategy
      Rails.logger.info("[Workflow] Starting execution: #{strategy_type}")
      result = execute_activity(
        WorkflowService.unified_workflow.activities.execute_container_activity,
        {
          strategy_type: strategy_type,
          strategy_input: input.strategy_input
        },
        timeout: calculate_execution_timeout(strategy_type, input)
      )

      # Step 3: Wait for signal if long-running (agent sessions)
      if input.wait_for_signal
        Rails.logger.info("[Workflow] Waiting for container_finished signal")
        Temporalio::Workflow.wait_condition { @finished }
        Rails.logger.info("[Workflow] Signal received, proceeding to cleanup")
      end

      # Step 4: Cleanup (always runs, even if execution failed)
      if result[:container_id].present?
        Rails.logger.info("[Workflow] Cleaning up container: #{result[:container_id]}")
        execute_activity(
          WorkflowService.unified_workflow.activities.cleanup_container_activity,
          {
            container_id: result[:container_id],
            session_id: input.strategy_input&.session_id
          },
          timeout: 60
        )
      end

      # Return result with pull info
      result.merge(
        image_pull_status: pull_result[:status],
        image_pull_duration: pull_result[:duration_seconds]
      )
    end

    private

    def calculate_execution_timeout(strategy_type, input)
      case strategy_type.to_sym
      when :tool_execution
        # Tool timeout + overhead for phases
        tool_timeout = input.strategy_input&.timeout || 300
        tool_timeout + 300 # Add 5 min for create/start/cleanup phases
      when :agent_auth, :agent_session
        # Agent sessions: phases only (exec waits for signal)
        300 # 5 minutes for all phases except exec
      else
        600 # Default 10 minutes
      end
    end
  end
end
```

---

## Strategy Execution Flows

### Pull Image Activity (Common for All)

```
┌─────────────────────────────────────────────────────────────┐
│ PullDockerImageActivity (Pre-Execution)                     │
│ Timeout: 10 minutes                                         │
└─────────────────────────────────────────────────────────────┘

Input: { image: "palad/claude-code:latest" }

Step 1: Check if image exists locally
├─ Try Docker::Image.get(image)
├─ If found → return { status: :cached } (< 1 second)
└─ If not found → proceed to pull

Step 2: Pull image from registry
├─ Docker::Image.create(fromImage: image)
├─ Stream progress logs:
│  ├─ "Pulling from palad/claude-code"
│  ├─ "a1b2c3d4: Downloading [========>  ] 50%"
│  └─ "Status: Downloaded newer image"
└─ Return { status: :pulled, duration_seconds: 45 }

Notes:
- Idempotent: safe to call multiple times
- Fast path: if cached, returns in < 1s
- Slow path: large custom tool images may take 5-10 min
- Retry-able: can retry failed pulls without re-executing workflow
- Visible: progress shown in Temporal UI and application logs
```

### 1. AgentAuthStrategy Flow

```
┌─────────────────────────────────────────────────────────────┐
│ AgentAuthStrategy (Authentication Setup)                    │
└─────────────────────────────────────────────────────────────┘

Phase: before_create (30s timeout)
├─ Validate input (agent_type, session_id, route_token)
├─ Resolve Docker image (palad/claude-code:latest)
├─ Get agent adapter (AgentCredentialsService.for(agent_type))
├─ Build env vars:
│  ├─ USER_ID, AGENT_TYPE
│  ├─ SESSION_TYPE=auth_setup
│  ├─ TTYD_PORT=7681, WATCHER_PORT=4040
│  ├─ HOME_DIR, AUTH_WATCH_PATH
│  └─ AGENT_SPECIFIC_VARS (from session.metadata)
├─ Build Traefik labels (route_token)
└─ Set context: { image, env_vars, labels, host_config }

Phase: create (60s timeout)
└─ Docker::Container.create(
     Image, Env, Labels, ExposedPorts: {7681, 4040},
     HostConfig: { NetworkMode, Tmpfs }
   )

Phase: before_start (30s timeout)
└─ (no-op for agent auth)

Phase: start (60s timeout)
├─ container.start
└─ wait_for_container_health (check Running status)

Phase: before_exec (120s timeout)
└─ (no-op for agent auth)

Phase: exec (INFINITE - waits for workflow signal)
├─ Build URLs:
│  ├─ websocket_url: /t/{route_token}/tty/ws
│  └─ watcher_url: /t/{route_token}/fs
└─ Set result: { container_id, websocket_url, watcher_url }
   (Workflow waits for user to complete auth via terminal)

Phase: before_cleanup (120s timeout)
├─ Extract auth files from container:
│  ├─ adapter.auth_file_paths (e.g., ~/.claude/config.json)
│  └─ Store in result[:auth_files] = { path => content }
└─ Parse and validate auth data

Phase: cleanup (30s timeout)
├─ container.stop(t: 5)
└─ container.remove
```

### 2. AgentSessionStrategy Flow

```
┌─────────────────────────────────────────────────────────────┐
│ AgentSessionStrategy (Pre-authenticated Session)            │
└─────────────────────────────────────────────────────────────┘

Phase: before_create (30s timeout)
├─ Validate input (agent_type, session_id, route_token, credential)
├─ Resolve Docker image
├─ Get MCP key from TerminalSession
├─ Build env vars:
│  ├─ USER_ID, AGENT_TYPE
│  ├─ SESSION_TYPE=agent_session
│  ├─ MCP_SERVER_URL, MCP_SESSION_KEY
│  ├─ HOME_DIR
│  └─ AGENT_SPECIFIC_VARS (from credential.metadata)
├─ Build Traefik labels
└─ Set context: { image, env_vars, labels, host_config }

Phase: create (60s timeout)
└─ Docker::Container.create(...)

Phase: before_start (30s timeout)
└─ (no-op)

Phase: start (60s timeout)
├─ container.start
└─ wait_for_container_health

Phase: before_exec (120s timeout)
└─ Load credentials into container:
   ├─ credential.write_to_container(container_id)
   └─ Write auth files to tmpfs (e.g., ~/.claude/config.json)

Phase: exec (INFINITE - waits for workflow signal)
├─ Build URLs (websocket_url, watcher_url)
└─ Set result: { container_id, websocket_url, watcher_url }
   (Workflow waits for user to finish session)

Phase: before_cleanup (120s timeout)
├─ Collect session artifacts:
│  ├─ Extract log files (if configured)
│  ├─ Extract output artifacts (e.g., ~/.agent/outputs/*)
│  └─ Extract session metadata
└─ Store in result[:artifacts] = { path => content }

Phase: cleanup (30s timeout)
├─ container.stop(t: 5)
└─ container.remove
```

### 3. ToolExecutionStrategy Flow

```
┌─────────────────────────────────────────────────────────────┐
│ ToolExecutionStrategy (Custom Tool Execution)               │
└─────────────────────────────────────────────────────────────┘

Phase: before_create (30s timeout)
├─ Validate input (tool, parameters, project)
├─ Resolve Docker image (from tool.docker_image)
├─ Resolve config items:
│  ├─ tool.required_config_items → ConfigItem.find(scope: project/company)
│  └─ Build env vars: { API_KEY=xxx, DB_URL=yyy }
├─ Build command (replace {{param}} placeholders)
└─ Set context: { image, env_vars, command, timeout }

Phase: create (60s timeout)
└─ Docker::Container.create(
     Image, Cmd: ["sleep", "infinity"], Env,
     HostConfig: {
       NetworkMode,
       Memory: 512MB,
       CpuQuota: 50% (prevent mining)
     }
   )

Phase: before_start (30s timeout)
└─ (no-op)

Phase: start (60s timeout)
├─ container.start
└─ wait_for_container_health

Phase: before_exec (120s timeout)
└─ Inject tool files into container:
   ├─ For each tool.tool_files:
   │  ├─ mkdir -p $(dirname path)
   │  └─ echo base64 | base64 -d > path
   └─ Set permissions

Phase: exec (5-30 min timeout, configurable per tool)
├─ Execute command in container:
│  └─ container.exec(["/bin/sh", "-c", command], wait: timeout)
├─ Capture stdout/stderr (with size limit: 1MB)
├─ Capture exit_code
└─ Set result: { exit_code, stdout, stderr, duration_ms }

   TIMEOUT ENFORCEMENT:
   - Default: 5 minutes (300s)
   - Max: 30 minutes (1800s)
   - User-configurable per tool (within limits)
   - If exceeded: kill container, return exit_code=124

Phase: before_cleanup (120s timeout)
└─ Collect output artifacts (if tool configured):
   ├─ Extract files from tool.output_paths (e.g., /workspace/output/*)
   └─ Store in result[:output_files] = { path => content }

Phase: cleanup (30s timeout)
├─ container.stop(t: 2)  # Shorter timeout for tools
└─ container.remove(force: true)
```

---

## Artifact Collection in before_cleanup

### Purpose of before_cleanup Phase

**Why separate phase?**
- Container is still running → can extract files via Docker API
- Happens before cleanup → guaranteed to run even if exec fails
- Timeout protected → won't hang if extraction fails
- Strategy-specific → each use case collects different artifacts

### AgentAuthStrategy Artifacts

```ruby
def before_cleanup(context)
  container = context[:container]
  agent_service = AgentCredentialsService.for(input[:agent_type])

  # Extract auth files from container
  auth_files = {}
  agent_service.adapter.auth_file_paths.each do |path|
    begin
      content = extract_file_from_container(container, path)
      auth_files[path] = content if content.present?
    rescue => e
      Rails.logger.warn("Failed to extract #{path}: #{e.message}")
    end
  end

  context[:result][:auth_files] = auth_files
  context[:result][:auth_completed] = auth_files.any?
end
```

### AgentSessionStrategy Artifacts

```ruby
def before_cleanup(context)
  container = context[:container]
  agent_service = AgentCredentialsService.for(input[:agent_type])

  artifacts = {}

  # 1. Collect session logs (if path configured in agent adapter)
  if agent_service.adapter.session_log_paths.present?
    agent_service.adapter.session_log_paths.each do |path|
      content = extract_file_from_container(container, path) rescue nil
      artifacts["logs/#{File.basename(path)}"] = content if content
    end
  end

  # 2. Collect output artifacts (if configured)
  if agent_service.adapter.output_artifact_paths.present?
    agent_service.adapter.output_artifact_paths.each do |path|
      # Can be glob pattern: /workspace/outputs/*
      files = list_files_in_container(container, path)
      files.each do |file_path|
        content = extract_file_from_container(container, file_path) rescue nil
        artifacts[file_path] = content if content
      end
    end
  end

  # 3. Store in session record
  context[:result][:artifacts] = artifacts
  context[:result][:artifacts_count] = artifacts.size

  # Optionally: store in database or S3
  if input[:store_artifacts] && artifacts.any?
    store_session_artifacts(input[:session_id], artifacts)
  end
end
```

### ToolExecutionStrategy Artifacts

```ruby
def before_cleanup(context)
  container = context[:container]
  tool = input[:tool]

  output_files = {}

  # Extract output files (if tool configured output_paths)
  if tool.output_paths.present?
    tool.output_paths.each do |path|
      begin
        content = extract_file_from_container(container, path)
        output_files[path] = content if content.present?
      rescue => e
        Rails.logger.warn("Failed to extract tool output #{path}: #{e.message}")
      end
    end
  end

  context[:result][:output_files] = output_files
end
```

---

## Timeout Enforcement Implementation

### Per-Phase Timeouts

```ruby
# app/services/container_execution_service.rb
class ContainerExecutionService
  def execute_phase(phase)
    timeout = phase_timeout(phase)

    Timeout.timeout(timeout) do
      @strategy.public_send(phase, @context) if @strategy.respond_to?(phase)
    end
  rescue Timeout::Error => e
    handle_timeout(phase, timeout)
  rescue StandardError => e
    handle_error(phase, e)
  end

  private

  def phase_timeout(phase)
    # Strategy can override timeouts
    if @strategy.respond_to?(:timeout_for)
      @strategy.timeout_for(phase)
    else
      default_timeout_for(phase)
    end
  end

  def default_timeout_for(phase)
    Settings.container_execution.timeouts[phase] || 30
  end

  def handle_timeout(phase, timeout)
    Rails.logger.error("[ContainerExecution] Phase #{phase} timed out after #{timeout}s")

    # Try emergency cleanup
    cleanup_on_timeout if phase != :cleanup

    raise ExecutionTimeout, "Phase #{phase} exceeded timeout of #{timeout}s"
  end
end
```

### Tool Execution Timeout (Anti-Mining Protection)

```ruby
# app/services/container_strategies/tool_execution_strategy.rb
module ContainerStrategies
  class ToolExecutionStrategy < BaseStrategy
    MAX_TOOL_TIMEOUT = 1800 # 30 minutes - absolute max
    DEFAULT_TOOL_TIMEOUT = 300 # 5 minutes

    def timeout_for(phase)
      return super(phase) unless phase == :exec

      # User can configure timeout per tool, but enforce limits
      requested = input[:timeout] || DEFAULT_TOOL_TIMEOUT
      [ requested.to_i, MAX_TOOL_TIMEOUT ].min
    end

    def exec(context)
      timeout = timeout_for(:exec)
      command = context[:command]

      Rails.logger.info("[ToolExecution] Starting command with #{timeout}s timeout")
      Rails.logger.info("[ToolExecution] Command: #{command}")

      start_time = Time.current

      begin
        result = Timeout.timeout(timeout) do
          execute_command_in_container(context[:container], command)
        end

        duration_ms = ((Time.current - start_time) * 1000).to_i

        context[:result] = {
          exit_code: result[:exit_code],
          stdout: truncate_output(result[:stdout]),
          stderr: truncate_output(result[:stderr]),
          duration_ms: duration_ms,
          timed_out: false
        }
      rescue Timeout::Error
        duration_ms = ((Time.current - start_time) * 1000).to_i

        # Kill container immediately
        context[:container].kill rescue nil

        context[:result] = {
          exit_code: 124, # Standard timeout exit code
          stdout: "",
          stderr: "Tool execution timed out after #{timeout} seconds",
          duration_ms: duration_ms,
          timed_out: true
        }

        Rails.logger.warn("[ToolExecution] TIMEOUT after #{timeout}s - container killed")
      end
    end

    private

    def execute_command_in_container(container, command)
      # Execute with output streaming to detect hangs early
      stdout_lines, stderr_lines, exit_code = container.exec(
        ["/bin/sh", "-c", command],
        stdout: true,
        stderr: true
      )

      {
        exit_code: exit_code,
        stdout: stdout_lines.join,
        stderr: stderr_lines.join
      }
    end

    def truncate_output(output, max_size: 1.megabyte)
      return "" if output.nil?
      return output if output.bytesize <= max_size

      output.byteslice(0, max_size) + "\n... (truncated, exceeded 1MB limit)"
    end
  end
end
```

---

## Security & Resource Limits

### Container Resource Limits (Anti-Abuse)

```ruby
# Applied in create phase for tool execution
def build_host_config
  {
    "NetworkMode" => DOCKER_NETWORK,
    "AutoRemove" => false,

    # Memory limits (prevent memory bombs)
    "Memory" => 512 * 1024 * 1024,        # 512MB hard limit
    "MemorySwap" => 512 * 1024 * 1024,    # Same as memory (no swap)
    "MemoryReservation" => 256 * 1024 * 1024, # 256MB soft limit

    # CPU limits (prevent CPU mining)
    "CpuPeriod" => 100_000,               # 100ms period
    "CpuQuota" => 50_000,                 # 50ms quota = 50% of 1 CPU
    "CpuShares" => 512,                   # Relative weight (default 1024)

    # Disk I/O limits
    "BlkioWeight" => 500,                 # I/O priority (10-1000)

    # Process limits
    "PidsLimit" => 100,                   # Max 100 processes

    # Network limits (optional, via tc in container)
    # "Ulimits" => [
    #   { "Name" => "nofile", "Soft" => 1024, "Hard" => 2048 }
    # ]
  }
end
```

### Detection of Mining/Abuse

```ruby
# Monitor CPU usage during execution
def exec(context)
  container = context[:container]
  monitoring_thread = start_monitoring(container)

  begin
    result = execute_command_in_container(container, context[:command])
    context[:result] = result
  ensure
    monitoring_thread.kill
  end
end

def start_monitoring(container)
  Thread.new do
    loop do
      sleep 10 # Check every 10 seconds

      stats = container.stats rescue nil
      next unless stats

      cpu_usage = calculate_cpu_percentage(stats)

      if cpu_usage > 90 # Sustained high CPU
        Rails.logger.warn("[ToolExecution] High CPU usage detected: #{cpu_usage}%")
        # Could auto-kill or flag for review
      end
    end
  end
end
```

---

## Summary

### Key Decisions

1. ✅ **Timeouts on every phase** - prevents hangs at any stage
2. ✅ **exec phase has strict limits** - 5-30 min max for tools, prevents mining
3. ✅ **before_cleanup collects artifacts** - auth files, logs, outputs
4. ✅ **Resource limits** - CPU 50%, Memory 512MB, enforced by Docker
5. ✅ **Output size limits** - 1MB max, prevents log bombs

### Artifacts Collection Summary

| Strategy Type      | before_cleanup Collects           | Storage                    |
|--------------------|-----------------------------------|----------------------------|
| AgentAuthStrategy  | Auth files (config.json, tokens) | AgentCredential record     |
| AgentSessionStrategy| Session logs, output artifacts   | TerminalSession.artifacts  |
| ToolExecutionStrategy| Tool output files               | ToolExecution.output_files |

---

## Implementation Status: COMPLETE ✅

**Completed:** 2026-02-04

### Stories Delivered

| Story | Name | Status |
|-------|------|--------|
| 8.1 | Container Execution Foundation | ✅ Done |
| 8.2 | Tool Execution Strategy Migration | ✅ Done |
| 8.3 | Agent Container Strategies Migration | ✅ Done |
| 8.4 | Unified Container Workflow | ✅ Done |
| 8.5 | Cleanup and Documentation | ✅ Done |

### Key Achievements

1. **Unified Entry Point**: `ContainerExecutionService.execute(strategy:, input:)`
2. **Strategy Pattern**: 3 concrete strategies (ToolExecution, AgentAuth, AgentSession)
3. **8-Phase Lifecycle**: Each phase with configurable timeout
4. **Artifact Collection**: Standardized via `before_cleanup` hook
5. **Anti-Abuse Protection**: CPU/memory limits, execution timeouts

### Files Created/Modified

**New Files:**
- `app/services/container_execution_service.rb` - Unified orchestrator
- `app/services/container_strategies/base_strategy.rb` - Abstract base
- `app/services/container_strategies/tool_execution_strategy.rb`
- `app/services/container_strategies/agent_auth_strategy.rb`
- `app/services/container_strategies/agent_session_strategy.rb`
- `app/services/container_workflow_service.rb` - Workflow helper
- `app/temporal/workflows/unified_container_workflow.rb`
- `app/temporal/activities/pull_docker_image_activity.rb`
- `app/temporal/activities/execute_container_activity.rb`
- `app/temporal/activities/cleanup_container_activity.rb`

**Removed:**
- `app/services/tool_execution_service.rb` - Replaced by strategy
- Deprecated methods from `container_service.rb`

### Code Metrics

- **Lines of code**: Reduced by ~35% (consolidation of duplicate logic)
- **Test coverage**: 56% (all new code tested)
- **Strategies**: Easy to extend - new container type = ~50 lines

### Extending the Framework

To add a new container type:

```ruby
# 1. Create strategy
class MyNewStrategy < ContainerStrategies::BaseStrategy
  def resolve_image
    "my-image:latest"
  end

  def exec(context)
    # Main execution logic
    context[:result] = { ... }
  end
end

# 2. Register in ExecuteContainerActivity
STRATEGY_CLASSES = {
  # existing...
  my_new_type: ContainerStrategies::MyNewStrategy
}

# 3. Use it
ContainerExecutionService.execute(
  strategy: MyNewStrategy.new(my_params),
  input: {}
)
```
