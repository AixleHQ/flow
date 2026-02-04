# frozen_string_literal: true

# Execute Container Activity
# Creates and starts container via strategy
#
# Input:
#   - strategy_type: tool_execution | agent_auth | agent_session
#   - strategy_input: Hash with strategy-specific parameters
#
# Output: Strategy execution result (container_id, urls, etc.)

module Activities
  class ExecuteContainerActivity < ContainerActivityBase
    def run(input)
      strategy_type = input.strategy_type
      strategy_input = input.strategy_input

      log(:info, "[Execute] Strategy: #{strategy_type}")

      # Build and execute strategy
      strategy = build_strategy_from_input(strategy_type, strategy_input)
      result = ContainerService.execute(strategy: strategy, input: strategy.input)

      # Update session for agent strategies
      if agent_strategy?(strategy_type)
        mark_session_running(strategy_input[:session_id], result[:container_id])
      end

      log(:info, "[Execute] Done, container: #{result[:container_id]}")
      result
    rescue ActiveRecord::RecordNotFound => e
      log(:error, "[Execute] Record not found: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue ContainerService::ExecutionError => e
      log(:error, "[Execute] Execution error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue ArgumentError => e
      log(:error, "[Execute] Invalid arguments: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue StandardError => e
      log(:error, "[Execute] Error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: true)
    end

    private

    def agent_strategy?(strategy_type)
      %w[agent_auth agent_session].include?(strategy_type.to_s)
    end
  end
end
