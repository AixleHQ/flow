# frozen_string_literal: true

# Unified Container Workflow
# Single workflow for all container executions (tools, agents)
#
# Steps:
# 1. Pull Docker image via strategy.pull_image
# 2. Execute container via strategy (create, start, exec)
# 3. Wait for signal (optional, for agent sessions)
# 4. Cleanup via strategy.before_cleanup + strategy.cleanup
#
# Input:
#   - strategy_type: :tool_execution | :agent_auth | :agent_session
#   - strategy_input: Hash with strategy-specific parameters
#
# Output:
#   - Result from strategy execution
#   - image_pull_status: :cached | :pulled
#   - cleanup_status: :cleaned_up | :not_found | etc

module Workflows
  class UnifiedContainerWorkflow < Base
    TOOL_DEFAULT_TIMEOUT = 300   # 5 minutes
    TOOL_MAX_TIMEOUT = 1800      # 30 minutes
    AGENT_PHASES_TIMEOUT = 300   # 5 minutes for phases
    IMAGE_PULL_TIMEOUT = 600     # 10 minutes
    CLEANUP_TIMEOUT = 120        # 2 minutes (includes artifact collection)
    AGENT_SIGNAL_TIMEOUT = 82_800 # 23 hours — buffer before server-side execution timeout (24h)

    workflow_signal
    def container_finished
      @finished = true
    end

    workflow_signal
    def container_cancelled
      @cancelled = true
      @finished = true
    end

    def run(input)
      @finished = false
      @cancelled = false
      @timed_out = false

      strategy_type = (input.strategy_type || input["strategy_type"]).to_sym
      strategy_input = input.strategy_input || input["strategy_input"]

      Temporalio::Workflow.logger.info("[UnifiedWorkflow] Starting: #{strategy_type}")

      # Step 1: Pull Docker image via strategy
      Temporalio::Workflow.logger.info("[UnifiedWorkflow] Pulling image")

      pull_result = execute_activity(
        activities.pull_docker_image_activity,
        { strategy_type: strategy_type.to_s, strategy_input: strategy_input },
        start_to_close_timeout: IMAGE_PULL_TIMEOUT
      )

      Temporalio::Workflow.logger.info("[UnifiedWorkflow] Image ready: #{pull_result[:status] || pull_result['status']}")

      # Step 2: Execute container strategy
      Temporalio::Workflow.logger.info("[UnifiedWorkflow] Executing container")

      result = execute_activity(
        activities.execute_container_activity,
        { strategy_type: strategy_type.to_s, strategy_input: strategy_input },
        start_to_close_timeout: calculate_execution_timeout(strategy_type, input)
      )

      container_id = result[:container_id] || result["container_id"]

      # Step 3: Wait for signal if long-running (agent sessions)
      if should_wait_for_signal?(strategy_type)
        Temporalio::Workflow.logger.info("[UnifiedWorkflow] Waiting for container_finished signal")

        Temporalio::Workflow.timeout(AGENT_SIGNAL_TIMEOUT) do
          Temporalio::Workflow.wait_condition { @finished }
        rescue Timeout::Error
          @timed_out = true
          Temporalio::Workflow.logger.warn("[UnifiedWorkflow] Timed out waiting for signal, proceeding to cleanup")
        end

        Temporalio::Workflow.logger.info("[UnifiedWorkflow] Done waiting, cancelled: #{@cancelled}, timed_out: #{@timed_out}")
      end

      # Step 4: Cleanup (before_cleanup runs artifact collection via strategy)
      cleanup_result = nil
      if container_id.present?
        Temporalio::Workflow.logger.info("[UnifiedWorkflow] Cleaning up: #{container_id}")

        cleanup_result = execute_activity(
          activities.cleanup_container_activity,
          {
            container_id: container_id,
            session_id: extract_session_id(input),
            strategy_type: strategy_type.to_s
          },
          start_to_close_timeout: CLEANUP_TIMEOUT
        )
      end

      # Return merged result
      build_result(result, pull_result, cleanup_result)
    end

    private

    def activities
      @activities ||= WorkflowService.unified_container_workflow.activities
    end

    def extract_session_id(input)
      input.strategy_input&.dig(:session_id) ||
        input.dig("strategy_input", "session_id")
    end

    def should_wait_for_signal?(strategy_type)
      %i[agent_auth agent_session].include?(strategy_type.to_sym)
    end

    def calculate_execution_timeout(strategy_type, input)
      case strategy_type.to_sym
      when :tool_execution
        # Tool timeout + overhead for phases (create, start, cleanup)
        tool_timeout = input.strategy_input&.dig(:timeout) ||
          input.dig("strategy_input", "timeout") ||
          TOOL_DEFAULT_TIMEOUT
        [ tool_timeout.to_i, TOOL_MAX_TIMEOUT ].min + 300 # Add 5 min overhead
      when :agent_auth, :agent_session
        # Agent sessions: only phases timeout (exec waits for signal)
        AGENT_PHASES_TIMEOUT
      else
        600 # Default 10 minutes
      end
    end

    def build_result(result, pull_result, cleanup_result)
      merged = result.dup

      # Add image pull info
      merged[:image_pull_status] = pull_result[:status] || pull_result["status"]
      merged[:image_pull_duration] = pull_result[:duration_seconds] || pull_result["duration_seconds"]

      # Add cleanup info (includes artifact collection results)
      if cleanup_result
        merged[:cleanup_status] = cleanup_result[:status] || cleanup_result["status"]
        merged[:artifacts_status] = cleanup_result[:artifacts_status] || cleanup_result["artifacts_status"]
        merged[:credential_id] = cleanup_result[:credential_id] || cleanup_result["credential_id"]
      end

      # Add status flags
      merged[:cancelled] = @cancelled
      merged[:timed_out] = @timed_out

      merged
    end
  end
end
