# frozen_string_literal: true

# Cleanup Stale Sessions Activity
# Finds terminal sessions stuck in active states and performs proper cleanup.
#
# Handles two cases:
#   1. Sessions in "started" that never became "running" (workflow failed silently)
#   2. Sessions in "running" that outlived their Temporal workflow (workflow terminated/expired)
#
# For each stale session:
#   - If container is still alive: runs full cleanup (collect usage → stop → remove → collected)
#   - If container is gone: transitions to failed
#
# Output:
#   - cleaned_started: count of started sessions cleaned
#   - cleaned_running: count of running sessions cleaned

module Activities
  class CleanupStaleSessionsActivity < ContainerActivityBase
    STARTED_STALE_THRESHOLD = 30.minutes
    RUNNING_STALE_THRESHOLD = 25.hours

    SESSION_TYPE_TO_STRATEGY = {
      "auth_setup" => "agent_auth",
      "agent_session" => "agent_session"
    }.freeze

    def run(_input = nil)
      cleaned_started = cleanup_stale(:started, STARTED_STALE_THRESHOLD)
      cleaned_running = cleanup_stale(:running, RUNNING_STALE_THRESHOLD)

      { cleaned_started: cleaned_started, cleaned_running: cleaned_running }
    end

    private

    def cleanup_stale(state, threshold)
      sessions = TerminalSession
        .where(state: state.to_s)
        .where(started_at: ...threshold.ago)

      if state == :started
        sessions = sessions.or(
          TerminalSession
            .where(state: state.to_s, started_at: nil)
            .where(created_at: ...threshold.ago)
        )
      end

      count = 0
      sessions.find_each do |session|
        try_cancel_workflow(session)
        cleanup_session(session)
        count += 1
        log(:info, "Cleaned stale #{state} session #{session.id}")
      rescue StandardError => e
        log(:warn, "Failed to clean session #{session.id}: #{e.message}")
      end
      count
    end

    def cleanup_session(session)
      container = session.container_id.present? ? find_container(session.container_id) : nil

      if container
        full_cleanup(session, container)
      else
        session.update(container_id: nil, error_message: "Stale session: workflow ended without cleanup")
        session.fail! if session.may_fail?
      end
    end

    def full_cleanup(session, container)
      strategy_type = SESSION_TYPE_TO_STRATEGY[session.session_type]
      strategy = strategy_type ? build_strategy_from_session(strategy_type, session) : nil

      context = { container: container, container_id: session.container_id, session: session, result: {} }

      if strategy
        strategy.before_cleanup(context)
        log(:info, "Collected artifacts for session #{session.id}")
      end

      cleanup_result = if strategy
                         strategy.cleanup(context)
      else
                         cleanup_without_strategy(session.container_id)
      end

      mark_session_collected(session.id, cleanup_result[:status])
    rescue StandardError => e
      log(:warn, "Full cleanup failed for session #{session.id}: #{e.message}, falling back to fail!")
      session.update(container_id: nil, error_message: "Stale session: cleanup failed — #{e.message}")
      session.fail! if session.may_fail?
    end

    def cleanup_without_strategy(container_id)
      runtime.stop_container(container_id, 5)
      runtime.remove_container(container_id)
      { status: :cleaned_up }
    rescue StandardError => e
      log(:warn, "Fallback cleanup failed: #{e.message}")
      { status: :failed }
    end

    def try_cancel_workflow(session)
      return if session.temporal_workflow_id.blank?

      ContainerWorkflowService.cancel_workflow(session.temporal_workflow_id)
    rescue StandardError => e
      log(:warn, "Failed to cancel workflow for session #{session.id}: #{e.message}")
    end
  end
end
