# frozen_string_literal: true

# Pull Docker Image Activity
# Pulls Docker image via strategy's pull_image method
#
# Input:
#   - strategy_type: tool_execution | agent_auth | agent_session
#   - strategy_input: Hash with strategy-specific parameters
#
# Output: { status: :cached|:pulled, image: "...", duration_seconds: N }

module Activities
  class PullDockerImageActivity < ContainerActivityBase
    def run(input)
      strategy_type = input.strategy_type
      strategy_input = input.strategy_input

      log(:info, "[Pull] Strategy: #{strategy_type}")

      strategy = build_strategy_from_input(strategy_type, strategy_input)
      result = strategy.pull_image

      log(:info, "[Pull] Done: #{result[:status]} (#{result[:duration_seconds]}s)")
      result
    rescue Docker::Error::NotFoundError => e
      log(:error, "[Pull] Image not found")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue Docker::Error::DockerError => e
      log(:error, "[Pull] Docker error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: true)
    rescue ArgumentError => e
      log(:error, "[Pull] Invalid arguments: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: false)
    rescue StandardError => e
      log(:error, "[Pull] Error: #{e.message}")
      raise TemporalExceptions.wrap(e, retryable: true)
    end
  end
end
