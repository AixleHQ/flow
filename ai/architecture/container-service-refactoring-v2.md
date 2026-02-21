# Container Service Refactoring v2

## Motivation

Current architecture has:
- 6 activity classes (3 agent + 3 tool) with significant duplication
- Timeouts scattered between workflow, ContainerService, and Settings
- `AgentSessionStrategy` fragile inheritance from `AgentAuthStrategy` (`.map!` hacks)
- Signal-waiting logic hardcoded in `AgentContainerWorkflow`
- Two separate workflows (`AgentContainerWorkflow`, `ToolExecutionWorkflow`) doing the same thing

## Target Architecture

```
ContainerWorkflow (generic, one for all)
  → resolve_manifest activity → phase configs from strategy
  → for each phase:
      → container_phase activity → ContainerService.new(strategy:, state:).run_phase(phase)
      → if await_signal → workflow waits for signal
  → ensure: cleanup phase activity (always runs)

ContainerService — thin phase runner, delegates before/phase/after to strategy
Strategy — defines behavior + phase_config (timeouts, signals, retries)
```

## Components

### 1. ContainerService (phase runner)

No timeout logic. No signal logic. Accumulates state from strategy return values.

```ruby
class ContainerService
  PHASES = %i[pull_image create_container start_container exec cleanup].freeze

  def initialize(strategy:, state: {})
    @strategy = strategy
    @state = state.deep_symbolize_keys
  end

  def run_phase(phase)
    @state.merge!(invoke(:"before_#{phase}"))
    @state.merge!(invoke(phase))
    @state.merge!(invoke(:"after_#{phase}"))
    @state
  end

  private

  def invoke(hook)
    return {} unless @strategy.respond_to?(hook)
    result = @strategy.public_send(hook, **@state)
    result.is_a?(Hash) ? result.deep_symbolize_keys : {}
  end
end
```

### 2. Strategy — phase_config

Each strategy defines per-phase metadata. The workflow uses this to set Temporal timeouts, decide on signal-waiting, and configure retries.

```ruby
# BaseStrategy
def phase_config(phase)
  { timeout: 300 }
end

# AgentAuthStrategy
def phase_config(phase)
  case phase
  when :pull_image    then { timeout: 600 }
  when :exec          then { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
  when :cleanup       then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
  else                     { timeout: 300 }
  end
end

# AgentSessionStrategy
def phase_config(phase)
  case phase
  when :pull_image    then { timeout: 600 }
  when :exec
    if non_interactive?
      { timeout: 85_800 }
    else
      { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
    end
  when :cleanup       then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
  else                     { timeout: 300 }
  end
end

# ToolExecutionStrategy
def phase_config(phase)
  case phase
  when :exec    then { timeout: [input[:timeout] || 300, 1800].min }
  when :cleanup then { timeout: 60, always: true }
  else               { timeout: 120 }
  end
end
```

### 3. Strategy inheritance (agent)

**Before:**
```
BaseStrategy
├── AgentAuthStrategy
│   └── AgentSessionStrategy (inherits auth, overrides with .map! hacks)
└── ToolExecutionStrategy
```

**After:**
```
BaseStrategy
├── AgentBaseStrategy (common: traefik, env vars, naming, validate, mark_session)
│   ├── AgentAuthStrategy (session_type=auth_setup, extract credentials)
│   └── AgentSessionStrategy (session_type=agent_session, load credentials, collect logs)
└── ToolExecutionStrategy
```

`AgentBaseStrategy` contains:
- `validate_input!`
- `resolve_image` (AGENT_IMAGES lookup)
- `build_base_env_vars` (common env: USER_ID, AGENT_TYPE, SESSION_ID, ROUTE_TOKEN, ports)
- `build_traefik_labels`
- `build_host_config` with tmpfs
- `build_exposed_ports`
- `mark_session_running`
- `services_ports`
- Traefik URL helpers

### 4. Activities

Single activity class (down from 6):

**ContainerPhaseActivity** — runs a single phase:
```ruby
def run(input)
  strategy = resolve_strategy(input)
  state = (input.state || {}).deep_symbolize_keys
  service = ContainerService.new(strategy: strategy, state: state)
  service.run_phase(input.phase.to_sym)
end
```

### 5. Manifest — computed by caller, passed as workflow input

`phase_config` is a pure function (no DB, no IO), so manifest is built
before starting the workflow in `ContainerWorkflowService`:

```ruby
# ContainerWorkflowService
def start_session(session:)
  strategy = session.strategy
  manifest = strategy.build_manifest  # { phases: { pull_image: { timeout: 600 }, ... } }

  TemporalService.start_workflow(
    container_workflow,
    { session_id: session.id, manifest: manifest }
  )
end
```

This avoids an extra activity just to read config.

### 6. Workflow (generic)

One workflow for all container types. Manifest comes from input.

```ruby
class ContainerWorkflow < Base
  workflow_signal
  def container_finished
    @signals[:container_finished] = true
  end

  def run(input)
    @signals = {}
    manifest = input.manifest
    context = {}
    execution_error = nil

    phases = ContainerService::PHASES - [:cleanup]
    phases.each do |phase|
      config = manifest[phase]
      context = execute_activity(:container_phase,
        { phase: phase, context: context, **input },
        start_to_close_timeout: config[:timeout]
      )
      if config[:await_signal]
        wait_for_signal(config[:await_signal], config[:signal_timeout])
      end
    end
  rescue => e
    execution_error = e.message
  ensure
    cleanup_config = manifest[:cleanup]
    execute_activity(:container_phase,
      { phase: :cleanup, context: context, error: execution_error, **input },
      start_to_close_timeout: cleanup_config[:timeout],
      retry_policy: build_retry(cleanup_config[:retry])
    )
  end
end
```

### 7. State between activities — explicit contracts

No magic context hash. Each strategy method declares its inputs via **keyword args** and returns a **Hash** of what it produced.

`ContainerService` accumulates state by merging return values:
```ruby
def run_phase(phase)
  @state.merge!(invoke(:"before_#{phase}"))
  @state.merge!(invoke(phase))
  @state.merge!(invoke(:"after_#{phase}"))
  @state
end

def invoke(hook)
  return {} unless @strategy.respond_to?(hook)
  result = @strategy.public_send(hook, **@state)
  result.is_a?(Hash) ? result : {}
end
```

Strategy methods use `**_` to swallow state they don't need:
```ruby
# Declares: needs container_id, produces: exit_code, stdout, stderr, ...
def exec(container_id:, **)
  container = resolve_container(container_id)
  # ...
  { exit_code: 0, stdout: "...", stderr: "" }
end

# Declares: needs nothing extra, produces: image, env_vars, labels, ...
def before_create_container(**)
  { image: resolve_image, env_vars: build_env_vars, labels: build_labels, ... }
end
```

Key state fields (flow between activities):
- `image:` — set by `pull_image` or `before_create_container`
- `container_id:` — set by `create_container`
- `session_id:` — passed from workflow input
- `error:` — set by workflow on failure, passed to cleanup

### 7. Files to change

**New:**
- `app/services/container_strategies/agent_base_strategy.rb`
- `app/temporal/activities/container/phase_activity.rb`
- `app/temporal/workflows/container_workflow.rb`

**Rewrite:**
- `app/services/container_service.rb` — thin phase runner
- `app/services/container_strategies/agent_auth_strategy.rb` — inherit AgentBaseStrategy
- `app/services/container_strategies/agent_session_strategy.rb` — inherit AgentBaseStrategy (not Auth)

**Remove:**
- `app/temporal/activities/agent/pull_image_activity.rb`
- `app/temporal/activities/agent/execute_container_activity.rb`
- `app/temporal/activities/agent/cleanup_container_activity.rb`
- `app/temporal/activities/tool/pull_image_activity.rb`
- `app/temporal/activities/tool/execute_container_activity.rb`
- `app/temporal/activities/tool/cleanup_container_activity.rb`
- `app/temporal/workflows/agent_container_workflow.rb`

**Update:**
- `app/temporal/workflows.yml` — single container_workflow entry
- `app/services/container_workflow_service.rb` — use new workflow
- `app/services/container_strategies/base_strategy.rb` — remove phase logic that moves to service

## Implementation Order

1. Create `AgentBaseStrategy`, extract shared code
2. Refactor `AgentAuthStrategy` → inherit `AgentBaseStrategy`
3. Refactor `AgentSessionStrategy` → inherit `AgentBaseStrategy` (not Auth)
4. Rewrite `ContainerService` as thin phase runner
5. Adapt strategies to new phase names (pull_image, create_container, start_container, exec, cleanup)
6. Add `phase_config` to all strategies
7. Create new activities (ResolveManifest + Phase)
8. Create generic `ContainerWorkflow`
9. Update `workflows.yml` and `ContainerWorkflowService`
10. Remove old activities and workflows
11. Update tests
