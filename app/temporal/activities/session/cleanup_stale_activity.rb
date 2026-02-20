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
  module Session
    class CleanupStaleActivity < Base
      STARTED_STALE_THRESHOLD = 30.minutes
      RUNNING_STALE_THRESHOLD = 25.hours

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
        container = session.container_id.present? ? runtime.resolve_container(session.container_id) : nil

        if container
          full_cleanup(session, container)
        else
          session.update(container_id: nil, error_message: "Stale session: workflow ended without cleanup")
          session.fail! if session.may_fail?
        end
      rescue StandardError => e
        log(:warn, "Failed to resolve container for session #{session.id}: #{e.message}")
        session.update(container_id: nil, error_message: "Stale session: #{e.message}")
        session.fail! if session.may_fail?
      end

      def full_cleanup(session, container)
        strategy = begin
          session.strategy
        rescue ArgumentError
          nil
        end

        context = { container: container, container_id: session.container_id, session: session, result: {} }

        if strategy
          strategy.before_cleanup(context)
          cleanup_result = strategy.cleanup(context)
        else
          cleanup_result = cleanup_without_strategy(session.container_id)
        end

        session.update(container_id: nil)
        session.collect! if session.may_collect?
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

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
