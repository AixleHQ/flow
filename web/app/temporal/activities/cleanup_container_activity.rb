# frozen_string_literal: true

# Cleanup Container Activity
# Runs strategy.before_cleanup and strategy.cleanup
#
# Input:
#   - container_id: Docker container ID
#   - session_id: TerminalSession ID
#   - strategy_type: Strategy type (agent_auth, agent_session, tool_execution)
#
# Output:
#   - status: :cleaned_up | :not_found | :force_removed | :failed
#   - Plus any results from strategy's before_cleanup (e.g. credential_id)

module Activities
  class CleanupContainerActivity < ContainerActivityBase
    def run(input)
      container_id = input.container_id
      session_id = input.session_id
      strategy_type = input.strategy_type

      log(:info, "[Cleanup] Container: #{container_id}, Strategy: #{strategy_type}")

      # Build context
      container = find_container(container_id)
      session = find_session(session_id)
      strategy = build_strategy_from_session(strategy_type, session)

      context = {
        container: container,
        container_id: container_id,
        session: session,
        result: {}
      }

      result = { container_id: container_id }

      # Step 1: before_cleanup (artifact collection)
      if strategy && container
        strategy.before_cleanup(context)
        result.merge!(context[:result] || {})
        log(:info, "[Cleanup] before_cleanup done")
      end

      # Step 2: cleanup (stop + remove container)
      cleanup_result = if strategy
                         strategy.cleanup(context)
      else
                         # Fallback: direct cleanup without strategy
                         cleanup_without_strategy(container_id)
      end
      result[:status] = cleanup_result[:status]

      # Step 3: Update session state
      mark_session_collected(session_id, cleanup_result[:status]) if session_id.present?

      result
    rescue StandardError => e
      log(:error, "[Cleanup] Error: #{e.message}")
      { status: :error, container_id: input.container_id, error: e.message }
    end

    private

    def cleanup_without_strategy(container_id)
      return { status: :skipped } if container_id.blank?

      runtime.stop_container(container_id, 5)
      runtime.remove_container(container_id)
      { status: :cleaned_up, container_id: container_id }
    rescue StandardError => e
      log(:warn, "[Cleanup] Fallback cleanup failed: #{e.message}")
      { status: :failed, container_id: container_id, error: e.message }
    end
  end
end
