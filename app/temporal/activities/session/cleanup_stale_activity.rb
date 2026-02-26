# frozen_string_literal: true

# Cleanup Stale Sessions Activity
# Finds terminal sessions stuck in active states and performs proper cleanup.
#
# Handles two cases:
#   1. Sessions in "running" that never became "ready" (workflow failed silently)
#   2. Sessions in "ready" that outlived their Temporal workflow (workflow terminated/expired)
#
# For each stale session:
#   - If container is still alive: runs full cleanup → finished
#   - If container is gone: transitions to failed

module Activities
  module Session
    class CleanupStaleActivity < Base
      RUNNING_STALE_THRESHOLD = 30.minutes
      READY_STALE_THRESHOLD = 25.hours

      MCP_SESSION_TTL = 7.days

      def run(_input = nil)
        cleaned_running = cleanup_stale(:running, RUNNING_STALE_THRESHOLD)
        cleaned_ready = cleanup_stale(:ready, READY_STALE_THRESHOLD)
        cleaned_mcp = cleanup_stale_mcp_sessions

        { cleaned_running: cleaned_running, cleaned_ready: cleaned_ready, cleaned_mcp: cleaned_mcp }
      end

      private

      def cleanup_stale(state, threshold)
        sessions = TerminalSession
          .where(state: state.to_s)
          .where(started_at: ...threshold.ago)

        if state == :running
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
          session.update(error_message: "Stale session: workflow ended without cleanup")
          session.fail! if session.may_fail?
        end
      rescue StandardError => e
        log(:warn, "Failed to resolve container for session #{session.id}: #{e.message}")
        session.update(error_message: "Stale session: #{e.message}")
        session.fail! if session.may_fail?
      end

      def full_cleanup(session, _container)
        strategy = session.strategy
        strategy.before_cleanup(container_id: session.container_id, session_id: session.id)
        strategy.cleanup(container_id: session.container_id)
        session.finish! if session.may_finish?
      rescue StandardError => e
        log(:warn, "Full cleanup failed for session #{session.id}: #{e.message}, falling back to fail!")
        session.update(error_message: "Stale session: cleanup failed — #{e.message}")
        session.fail! if session.may_fail?
      end

      def try_cancel_workflow(session)
        session.cancel!
      rescue StandardError => e
        log(:warn, "Failed to cancel workflow for session #{session.id}: #{e.message}")
      end

      def cleanup_stale_mcp_sessions
        count = 0

        ActionMCP::Session
          .where("created_at < ?", MCP_SESSION_TTL.ago)
          .find_each do |session|
            session.destroy
            count += 1
          rescue StandardError => e
            log(:warn, "Failed to clean MCP session #{session.id}: #{e.message}")
          end

        count
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
