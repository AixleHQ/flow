# Story 8.1: Container Execution Framework Foundation

Status: ready-for-dev

## Story

As a system,
I want a unified container execution framework with lifecycle hooks and timeout protection,
So that all container-based workloads (agents, tools, future use cases) use consistent execution logic with proper resource limits.

## Architecture Decision

**Approach:** Strategy Pattern + Lifecycle Hooks + Per-Phase Timeouts

**Key Components:**
- `ContainerExecutionService` - Orchestrator executing 8 lifecycle phases
- `BaseStrategy` - Abstract base class with default implementations
- `PullDockerImageActivity` - Separate Temporal activity for image pulling

```
┌─────────────────────────────────────┐
│  ContainerExecutionService.execute  │
│  (strategy:, input:)                │
└──────────────┬──────────────────────┘
               │
               ▼
    ┌──────────────────────┐
    │  Lifecycle Phases:   │
    │  1. before_create    │ ← Strategy implements
    │  2. create           │ ← Base/Strategy
    │  3. before_start     │ ← Strategy implements
    │  4. start            │ ← Base implements
    │  5. before_exec      │ ← Strategy implements
    │  6. exec             │ ← Strategy implements
    │  7. before_cleanup   │ ← Strategy implements
    │  8. cleanup          │ ← Base implements
    └──────────────────────┘
         Each phase has timeout protection
```

## Acceptance Criteria

1. ✅ `ContainerExecutionService` executes 8 lifecycle phases with timeouts
2. ✅ `BaseStrategy` provides default implementations for common phases
3. ✅ Per-phase timeouts configured in `config/settings.yml`
4. ✅ `PullDockerImageActivity` pulls images with 10-minute timeout
5. ✅ Error handling with phase-specific logging
6. ✅ Shared context passed between phases
7. ✅ Unit tests for service and base strategy

## Tasks

### Task 1: Create ContainerExecutionService (AC: 1, 5, 6)

- [ ] Create `app/services/container_execution_service.rb`
- [ ] Implement lifecycle phases:
  ```ruby
  def lifecycle_phases
    [:before_create, :create, :before_start, :start,
     :before_exec, :exec, :before_cleanup, :cleanup]
  end
  ```
- [ ] Implement phase execution with timeout:
  ```ruby
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
  ```
- [ ] Implement shared context between phases: `@context = {}`
- [ ] Add phase-specific error logging
- [ ] Add emergency cleanup on timeout

**Acceptance:** Service executes all phases in order with timeout protection

---

### Task 2: Create BaseStrategy (AC: 2)

- [ ] Create `app/services/container_strategies/base_strategy.rb`
- [ ] Implement default `before_create`:
  ```ruby
  def before_create(context)
    context[:image] = resolve_image
    context[:env_vars] = build_env_vars
    context[:labels] = build_labels
    context[:host_config] = build_host_config
  end
  ```
- [ ] Implement `create`:
  ```ruby
  def create(context)
    context[:container] = Docker::Container.create(
      "Image" => context[:image],
      "Env" => context[:env_vars],
      "Labels" => context[:labels],
      "HostConfig" => context[:host_config]
    )
  end
  ```
- [ ] Implement `start` with health check:
  ```ruby
  def start(context)
    context[:container].start
    wait_for_container_health(context[:container])
  end
  ```
- [ ] Implement default `cleanup`:
  ```ruby
  def cleanup(context)
    container = context[:container]
    container&.stop("t" => 5)
    container&.remove
  end
  ```
- [ ] Add template methods: `resolve_image`, `build_env_vars`, `build_labels`, `build_host_config`
- [ ] Add `wait_for_container_health` helper

**Acceptance:** BaseStrategy provides working defaults for common phases

---

### Task 3: Configure Timeouts (AC: 3)

- [ ] Add to `config/settings.yml`:
  ```yaml
  container_execution:
    timeouts:
      pull_image: 600        # 10 minutes for large images
      before_create: 30      # 30 seconds
      create: 60             # 1 minute
      before_start: 30       # 30 seconds
      start: 60              # 1 minute
      before_exec: 120       # 2 minutes
      exec_default: 300      # 5 minutes (tools)
      exec_max: 1800         # 30 minutes (max for tools)
      before_cleanup: 120    # 2 minutes
      cleanup: 30            # 30 seconds

    limits:
      tool_execution:
        memory_mb: 512
        cpu_percent: 50
        max_timeout: 1800
  ```
- [ ] Update ContainerExecutionService to read from Settings
- [ ] Allow strategy to override timeouts via `timeout_for(phase)` method

**Acceptance:** All timeouts configurable and enforced

---

### Task 4: Create PullDockerImageActivity (AC: 4)

- [ ] Create `app/temporal/activities/pull_docker_image_activity.rb`
- [ ] Implement idempotent pull logic:
  ```ruby
  def run(input)
    image = input.image

    # Fast path: image already cached
    begin
      Docker::Image.get(image)
      return { status: :cached, image: image }
    rescue Docker::Error::NotFoundError
      # Pull from registry
    end

    # Slow path: pull with progress
    start_time = Time.current
    Docker::Image.create("fromImage" => image) do |chunk|
      log_pull_progress(chunk)
    end

    duration = (Time.current - start_time).to_i
    { status: :pulled, image: image, duration_seconds: duration }
  end
  ```
- [ ] Add progress logging
- [ ] Set activity timeout to 10 minutes
- [ ] Handle Docker errors gracefully

**Acceptance:** Activity pulls images with idempotent caching

---

### Task 5: Add Resource Limits Helper (AC: 3)

- [ ] Add to BaseStrategy:
  ```ruby
  def build_host_config_with_limits
    {
      "NetworkMode" => DOCKER_NETWORK,
      "AutoRemove" => false,
      "Memory" => Settings.container_execution.limits.tool_execution.memory_mb * 1024 * 1024,
      "MemorySwap" => Settings.container_execution.limits.tool_execution.memory_mb * 1024 * 1024,
      "CpuPeriod" => 100_000,
      "CpuQuota" => Settings.container_execution.limits.tool_execution.cpu_percent * 1000,
      "PidsLimit" => 100
    }
  end
  ```
- [ ] Document anti-mining protection

**Acceptance:** Resource limits prevent abuse

---

### Task 6: Write Tests (AC: 7)

- [ ] Test `ContainerExecutionService`:
  - Phase execution order
  - Timeout enforcement
  - Error handling
  - Context sharing
- [ ] Test `BaseStrategy`:
  - Default implementations
  - Template method pattern
  - Health checks
- [ ] Test `PullDockerImageActivity`:
  - Cached images (fast path)
  - Pull from registry (slow path)
  - Error handling
- [ ] Integration test: full lifecycle execution

**Acceptance:** >90% code coverage, all edge cases tested

---

## Implementation Notes

### Error Handling Strategy

```ruby
def handle_timeout(phase, timeout)
  Rails.logger.error("[ContainerExecution] Phase #{phase} timed out after #{timeout}s")

  # Try emergency cleanup (don't fail if cleanup fails)
  emergency_cleanup if phase != :cleanup

  raise ExecutionTimeout, "Phase #{phase} exceeded timeout of #{timeout}s"
end

def emergency_cleanup
  return unless @context[:container]

  @context[:container].kill rescue nil
  @context[:container].remove(force: true) rescue nil
rescue => e
  Rails.logger.error("[ContainerExecution] Emergency cleanup failed: #{e.message}")
end
```

### Context Structure

```ruby
# Shared across all phases
@context = {
  # Input
  input: { ... },

  # Populated by before_create
  image: "palad/claude-code:latest",
  env_vars: ["USER_ID=1", ...],
  labels: { ... },
  host_config: { ... },

  # Populated by create
  container: Docker::Container instance,

  # Populated by exec
  result: { container_id:, websocket_url:, ... },

  # Populated by before_cleanup (optional)
  artifacts: { path => content }
}
```

---

## File List

### New Files
- `app/services/container_execution_service.rb`
- `app/services/container_strategies/base_strategy.rb`
- `app/temporal/activities/pull_docker_image_activity.rb`
- `test/services/container_execution_service_test.rb`
- `test/services/container_strategies/base_strategy_test.rb`
- `test/temporal/activities/pull_docker_image_activity_test.rb`

### Modified Files
- `config/settings.yml` (add container_execution config)

---

## Dependencies

- Docker gem (already installed)
- Temporal gem (already installed)
- Settings gem (already installed)

---

## Next Stories

- Story 8.2: Tool Migration (implement ToolExecutionStrategy)
- Story 8.3: Agent Migration (implement AgentAuthStrategy, AgentSessionStrategy)

---

## Dev Agent Record

**Agent Model:** (to be filled during implementation)

**Completion Notes:** (to be filled during implementation)
