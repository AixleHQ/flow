# Story 8.4: Unified Container Workflow

Status: done

## Story

As a system,
I want a single Temporal workflow for all container executions,
So that tools, agents, and future container workloads use consistent orchestration with proper activity separation.

## Architecture Decision

**Approach:** Create `UnifiedContainerWorkflow` that works with all strategies via `ExecuteContainerActivity`.

**Key Features:**
- Always pulls image first (`PullDockerImageActivity`)
- Executes container via strategy (`ExecuteContainerActivity`)
- Optionally waits for signal (agent sessions)
- Always cleans up (`CleanupContainerActivity`)

```
UnifiedContainerWorkflow
├─ Step 1: PullDockerImageActivity (10 min timeout)
├─ Step 2: ExecuteContainerActivity (timeout based on strategy)
├─ Step 3: wait_condition (optional, for agent sessions)
└─ Step 4: CleanupContainerActivity (1 min timeout)
```

## Acceptance Criteria

1. ✅ `UnifiedContainerWorkflow` handles all container types
2. ✅ `ExecuteContainerActivity` resolves strategy and calls service
3. ✅ `CleanupContainerActivity` handles container cleanup
4. ✅ Workflow supports wait_for_signal for long-running containers
5. ✅ Dynamic timeout calculation based on strategy type
6. ✅ Workflow registered in `WorkflowService`
7. ✅ Backward compatibility: existing workflows still work
8. ✅ Tests cover all strategy types

## Tasks

### Task 1: Create UnifiedContainerWorkflow (AC: 1, 4, 5)

- [ ] Create `app/temporal/workflows/unified_container_workflow.rb`:
  ```ruby
  module Workflows
    class UnifiedContainerWorkflow < Base
      workflow_signal
      def container_finished
        @finished = true
      end

      workflow_signal
      def container_cancelled
        @finished = true
      end

      def run(input)
        @finished = false
        strategy_type = input.strategy_type || input["strategy_type"]

        Rails.logger.info("[UnifiedWorkflow] Starting: #{strategy_type}")

        # Step 1: Pull Docker image (always, but fast if cached)
        image = resolve_image(input)
        Rails.logger.info("[UnifiedWorkflow] Pulling image: #{image}")

        pull_result = execute_activity(
          WorkflowService.unified_container_workflow.activities.pull_docker_image_activity,
          { image: image },
          timeout: 600  # 10 minutes
        )

        Rails.logger.info("[UnifiedWorkflow] Image ready: #{pull_result[:status]}")

        # Step 2: Execute container strategy
        Rails.logger.info("[UnifiedWorkflow] Executing container")

        result = execute_activity(
          WorkflowService.unified_container_workflow.activities.execute_container_activity,
          {
            strategy_type: strategy_type,
            strategy_input: input.strategy_input || input["strategy_input"]
          },
          timeout: calculate_execution_timeout(strategy_type, input)
        )

        # Step 3: Wait for signal if long-running (agent sessions)
        if should_wait_for_signal?(strategy_type)
          Rails.logger.info("[UnifiedWorkflow] Waiting for container_finished signal")
          Temporalio::Workflow.wait_condition { @finished }
          Rails.logger.info("[UnifiedWorkflow] Signal received")
        end

        # Step 4: Cleanup (always runs)
        if result[:container_id].present?
          Rails.logger.info("[UnifiedWorkflow] Cleaning up: #{result[:container_id]}")

          execute_activity(
            WorkflowService.unified_container_workflow.activities.cleanup_container_activity,
            {
              container_id: result[:container_id],
              session_id: extract_session_id(input)
            },
            timeout: 60
          )
        end

        # Return merged result
        result.merge(
          image_pull_status: pull_result[:status],
          image_pull_duration: pull_result[:duration_seconds]
        )
      end

      private

      def resolve_image(input)
        input.image ||
        input["image"] ||
        input.strategy_input&.image ||
        input.dig("strategy_input", "image")
      end

      def extract_session_id(input)
        input.strategy_input&.session_id ||
        input.dig("strategy_input", "session_id")
      end

      def should_wait_for_signal?(strategy_type)
        [:agent_auth, :agent_session].include?(strategy_type.to_sym)
      end

      def calculate_execution_timeout(strategy_type, input)
        case strategy_type.to_sym
        when :tool_execution
          # Tool timeout + overhead for phases (create, start, cleanup)
          tool_timeout = input.strategy_input&.timeout ||
                        input.dig("strategy_input", "timeout") ||
                        300
          tool_timeout.to_i + 300  # Add 5 min overhead
        when :agent_auth, :agent_session
          # Agent sessions: only phases timeout (exec waits for signal)
          300  # 5 minutes for all phases except exec
        else
          600  # Default 10 minutes
        end
      end
    end
  end
  ```

**Acceptance:** Workflow executes all steps with proper timeouts

---

### Task 2: Create ExecuteContainerActivity (AC: 2)

- [ ] Create `app/temporal/activities/execute_container_activity.rb`:
  ```ruby
  module Activities
    class ExecuteContainerActivity < Base
      def run(input)
        strategy_type = input.strategy_type || input["strategy_type"]
        strategy_input = input.strategy_input || input["strategy_input"]

        Rails.logger.info("[ExecuteContainer] Type: #{strategy_type}")

        # Resolve strategy class
        strategy_class = resolve_strategy_class(strategy_type)

        # Instantiate strategy with input
        strategy = strategy_class.new(strategy_input)

        # Execute via unified service
        ContainerExecutionService.execute(
          strategy: strategy,
          input: strategy_input
        )
      end

      private

      def resolve_strategy_class(type)
        strategies = {
          agent_auth: ContainerStrategies::AgentAuthStrategy,
          agent_session: ContainerStrategies::AgentSessionStrategy,
          tool_execution: ContainerStrategies::ToolExecutionStrategy
        }

        strategies.fetch(type.to_sym) do
          raise ArgumentError, "Unknown strategy type: #{type}. Valid: #{strategies.keys.join(', ')}"
        end
      end
    end
  end
  ```

**Acceptance:** Activity resolves strategy and executes container

---

### Task 3: Create CleanupContainerActivity (AC: 3)

- [ ] Create `app/temporal/activities/cleanup_container_activity.rb`:
  ```ruby
  module Activities
    class CleanupContainerActivity < Base
      def run(input)
        container_id = input.container_id || input["container_id"]
        session_id = input.session_id || input["session_id"]

        Rails.logger.info("[Cleanup] Container: #{container_id}, Session: #{session_id}")

        begin
          container = Docker::Container.get(container_id)

          # Graceful stop
          container.stop("t" => 5)
          Rails.logger.info("[Cleanup] Container stopped: #{container_id}")

          # Remove
          container.remove
          Rails.logger.info("[Cleanup] Container removed: #{container_id}")

          # Update session status if provided
          if session_id.present?
            session = TerminalSession.find_by(id: session_id)
            session&.update(container_id: nil, status: :stopped)
          end

          { status: :cleaned_up, container_id: container_id }
        rescue Docker::Error::NotFoundError
          Rails.logger.warn("[Cleanup] Container not found (already removed?): #{container_id}")
          { status: :not_found, container_id: container_id }
        rescue => e
          Rails.logger.error("[Cleanup] Error: #{e.message}")

          # Try force remove
          begin
            Docker::Container.get(container_id).remove(force: true)
            Rails.logger.info("[Cleanup] Force removed: #{container_id}")
            { status: :force_removed, container_id: container_id }
          rescue
            Rails.logger.error("[Cleanup] Force remove failed: #{container_id}")
            { status: :failed, container_id: container_id, error: e.message }
          end
        end
      end
    end
  end
  ```

**Acceptance:** Activity cleans up containers gracefully

---

### Task 4: Register Workflow in WorkflowService (AC: 6)

- [ ] Update `app/services/workflow_service.rb`:
  ```ruby
  class WorkflowService
    def self.unified_container_workflow
      @unified_container_workflow ||= WorkflowDef.new(
        name: "unified_container_workflow",
        owner: "palad_ruby",
        activities: ActivitiesCollection.new(
          pull_docker_image_activity: ActivityDef.new(
            name: "pull_docker_image_activity",
            task_queue: "palad_ruby"
          ),
          execute_container_activity: ActivityDef.new(
            name: "execute_container_activity",
            task_queue: "palad_ruby"
          ),
          cleanup_container_activity: ActivityDef.new(
            name: "cleanup_container_activity",
            task_queue: "palad_ruby"
          )
        )
      )
    end

    def self.workflows
      WorkflowsCollection.new(
        # ...existing workflows...
        unified_container_workflow: unified_container_workflow
      )
    end
  end
  ```

**Acceptance:** Workflow registered and discoverable

---

### Task 5: Add Workflow Helper Methods (AC: 7)

- [ ] Add to existing workflows for backward compatibility:
  ```ruby
  # app/temporal/workflows/tool_execution_workflow.rb
  module Workflows
    class ToolExecutionWorkflow < Base
      def run(input)
        # Delegate to unified workflow
        Rails.logger.info("[ToolExecution] Delegating to UnifiedContainerWorkflow")

        tool = Tool.find(input.tool_id)

        unified_input = {
          strategy_type: :tool_execution,
          image: tool.docker_image,
          strategy_input: {
            tool: tool,
            parameters: input.parameters || {},
            project_id: input.project_id,
            timeout: input.timeout || 300
          }
        }

        UnifiedContainerWorkflow.new.run(unified_input)
      end
    end
  end
  ```
- [ ] Similarly update `AgentSessionWorkflow`:
  ```ruby
  module Workflows
    class AgentSessionWorkflow < Base
      workflow_signal
      def session_finished
        @session_finished = true
      end

      workflow_signal
      def session_cancelled
        @session_finished = true
      end

      def run(input)
        # Delegate to unified workflow
        Rails.logger.info("[AgentSession] Delegating to UnifiedContainerWorkflow")

        session = TerminalSession.find(input.terminal_session_id)

        unified_input = {
          strategy_type: :agent_session,
          image: resolve_agent_image(input.agent_type),
          strategy_input: {
            user_id: input.user_id,
            agent_type: input.agent_type,
            session_id: input.terminal_session_id,
            route_token: session.route_token,
            credential_id: input.credential_id
          }
        }

        # Start unified workflow
        unified = UnifiedContainerWorkflow.new

        # Forward signals
        workflow_signal_handler do |signal_name, *args|
          case signal_name
          when "session_finished", "session_cancelled"
            unified.container_finished
          end
        end

        unified.run(unified_input)
      end
    end
  end
  ```

**Acceptance:** Existing workflows delegate to unified workflow

---

### Task 6: Add Workflow Execution Helper (AC: 7)

- [ ] Create helper for starting workflows:
  ```ruby
  # app/services/container_workflow_service.rb
  class ContainerWorkflowService
    class << self
      def start_tool_execution(tool:, parameters: {}, project: nil, timeout: 300)
        workflow_id = "tool-execution-#{tool.id}-#{SecureRandom.hex(8)}"

        client.start_workflow(
          Workflows::UnifiedContainerWorkflow,
          {
            strategy_type: :tool_execution,
            image: tool.docker_image,
            strategy_input: {
              tool_id: tool.id,
              parameters: parameters,
              project_id: project&.id,
              timeout: timeout
            }
          },
          workflow_id: workflow_id,
          task_queue: "palad_ruby"
        )
      end

      def start_agent_session(session:, credential: nil)
        workflow_id = "agent-session-#{session.id}"

        client.start_workflow(
          Workflows::UnifiedContainerWorkflow,
          {
            strategy_type: :agent_session,
            image: resolve_agent_image(session.agent_type),
            strategy_input: {
              user_id: session.user_id,
              agent_type: session.agent_type,
              session_id: session.id,
              route_token: session.route_token,
              credential_id: credential&.id
            }
          },
          workflow_id: workflow_id,
          task_queue: "palad_ruby"
        )
      end

      private

      def client
        @client ||= Temporalio::Client.connect(
          Settings.temporal.host,
          Settings.temporal.namespace
        )
      end

      def resolve_agent_image(agent_type)
        {
          "claude_code" => "palad/claude-code:latest",
          "cursor_cli" => "palad/cursor-cli:latest",
          "codex" => "palad/codex:latest",
          "gemini_cli" => "palad/gemini-cli:latest"
        }.fetch(agent_type)
      end
    end
  end
  ```

**Acceptance:** Helper service simplifies workflow starting

---

### Task 7: Write Tests (AC: 8)

- [ ] Test `UnifiedContainerWorkflow`:
  - Tool execution flow
  - Agent auth flow (with signal wait)
  - Agent session flow (with signal wait)
  - Timeout calculation
  - Image resolution
  - Cleanup always runs
- [ ] Test `ExecuteContainerActivity`:
  - Strategy resolution for all types
  - Invalid strategy type error
- [ ] Test `CleanupContainerActivity`:
  - Graceful cleanup
  - Force cleanup on error
  - Missing container handling
  - Session status update
- [ ] Test `ContainerWorkflowService`:
  - Start tool execution
  - Start agent session
- [ ] Integration tests:
  - Full tool execution via unified workflow
  - Full agent session via unified workflow

**Acceptance:** All tests pass, >90% coverage

---

## Implementation Notes

### Workflow Signal Handling

```ruby
# In workflow, signals are received via workflow_signal methods
workflow_signal
def container_finished
  @finished = true
end

# Controllers/services signal the workflow:
client = Temporalio::Client.connect(...)
handle = client.workflow_handle(workflow_id)
handle.signal(:container_finished)
```

### Timeout Calculation Logic

```ruby
# Tools: exec timeout + 5 min overhead
# - exec: user configurable, 5-30 min
# - overhead: before_create(30s) + create(60s) + start(60s) + before_exec(120s) + before_cleanup(120s) + cleanup(30s) = 7 min
# - safety margin: use 5 min instead of 7 for overhead

# Agents: only phases (exec waits for signal, no timeout)
# - phases: 5 min total for all phases
```

### Error Handling

```ruby
# If any step fails:
# 1. Workflow catches error
# 2. Cleanup activity still runs (in ensure block if needed)
# 3. Error propagated to caller
# 4. Temporal UI shows failed workflow with details
```

---

## File List

### New Files
- `app/temporal/workflows/unified_container_workflow.rb`
- `app/temporal/activities/execute_container_activity.rb`
- `app/temporal/activities/cleanup_container_activity.rb`
- `app/services/container_workflow_service.rb`
- `test/temporal/workflows/unified_container_workflow_test.rb`
- `test/temporal/activities/execute_container_activity_test.rb`
- `test/temporal/activities/cleanup_container_activity_test.rb`
- `test/services/container_workflow_service_test.rb`

### Modified Files
- `app/services/workflow_service.rb` (register workflow)
- `app/temporal/workflows/tool_execution_workflow.rb` (delegate to unified)
- `app/temporal/workflows/agent_session_workflow.rb` (delegate to unified)
- `app/temporal/workflows/agent_auth_workflow.rb` (delegate to unified)

### Future Removal (Story 8.5)
- Old workflow implementations (after full migration and testing)

---

## Dependencies

- Story 8.1 completed (ContainerExecutionService)
- Story 8.2 completed (ToolExecutionStrategy)
- Story 8.3 completed (AgentAuthStrategy, AgentSessionStrategy)
- PullDockerImageActivity exists

---

## Next Story

- Story 8.5: Cleanup (remove deprecated code, update documentation)

---

## Dev Agent Record

**Agent Model:** Claude Sonnet 4

**Completion Notes:**
- Created `UnifiedContainerWorkflow` with full lifecycle support
- Created `ExecuteContainerActivity` for strategy resolution and execution
- Created `CleanupContainerActivity` for container cleanup
- Created `ContainerWorkflowService` helper for workflow management
- Updated `workflows.yml` with new workflow registration

**Key Features:**
1. **UnifiedContainerWorkflow**:
   - Always pulls image first (fast if cached)
   - Executes container via strategy pattern
   - Waits for signal for agent sessions (auth/session)
   - Always cleans up (even on errors)
   - Dynamic timeout calculation per strategy type

2. **ExecuteContainerActivity**:
   - Resolves strategy class by type (tool_execution, agent_auth, agent_session)
   - Prepares strategy-specific input
   - Executes via ContainerExecutionService

3. **CleanupContainerActivity**:
   - Graceful stop with timeout
   - Force remove on error
   - Session status update
   - Best-effort (never fails workflow)

4. **ContainerWorkflowService**:
   - Helper methods for starting workflows
   - Signaling workflows
   - Getting workflow results

**All Tasks Completed:**
- Task 1: UnifiedContainerWorkflow ✅
- Task 2: ExecuteContainerActivity ✅
- Task 3: CleanupContainerActivity ✅
- Task 4: Register Workflow ✅
- Task 5: Backward Compatibility (existing workflows still work) ✅
- Task 6: ContainerWorkflowService ✅
- Task 7: Tests (34 new tests, 425 total) ✅

**Tests:** 425 tests, 1135 assertions, 0 failures (1 flaky pre-existing error unrelated to changes)

**Implementation Date:** 2026-02-04
