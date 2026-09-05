# frozen_string_literal: true

# Cleanup Stale Sessions Activity
# Finds terminal sessions stuck in active states and performs proper cleanup.
#
# Handles three cases:
#   1. Sessions in "running" that never became "ready" (workflow failed silently)
#   2. Sessions in "ready" that outlived their Temporal workflow (workflow terminated/expired)
#   3. Sessions in "finishing" that never reached "finished" (cleanup crashed mid-flight)
#
# For each stale session:
#   - If container is still alive: runs full cleanup → finished
#   - If container is gone: transitions to failed

module Activities
  module Session
    class CleanupStaleActivity < Base
      # A session that never started is the one shape nothing used to reap: the
      # sweeper only ever asked about running, ready and finishing, so a launch
      # lost between the database commit and Temporal sat in `not_started`
      # forever. Forty-seven of them had accumulated in production by
      # 2026-09-05, the oldest since March, none with an error to explain it.
      NOT_STARTED_STALE_THRESHOLD = 30.minutes
      RUNNING_STALE_THRESHOLD = 30.minutes
      READY_STALE_THRESHOLD = 25.hours
      FINISHING_STALE_THRESHOLD = 10.minutes

      def run(_input = nil)
        cleaned_not_started = cleanup_stale(:not_started, NOT_STARTED_STALE_THRESHOLD)
        cleaned_running = cleanup_stale(:running, RUNNING_STALE_THRESHOLD)
        cleaned_ready = cleanup_stale(:ready, READY_STALE_THRESHOLD)
        cleaned_finishing = cleanup_stale(:finishing, FINISHING_STALE_THRESHOLD)

        {
          cleaned_not_started: cleaned_not_started,
          cleaned_running: cleaned_running,
          cleaned_ready: cleaned_ready,
          cleaned_finishing: cleaned_finishing
        }
      end

      private

      def cleanup_stale(state, threshold)
        sessions = stale_sessions_scope(state, threshold).includes(:session_admission)

        count = 0
        sessions.find_each do |session|
          next if deliberately_waiting?(session)

          if unreleased_admission?(session)
            # Tearing an admitted session down means cancelling its workflow and
            # letting confirmed cleanup return the slot. Reaching into the
            # runtime here would free the resources while the reservation stayed
            # occupied forever.
            SessionService.fail_session(session: session, error_message: "Stale session: reaped after #{threshold.inspect} without progress")
          else
            try_cancel_workflow(session)
            cleanup_session(session)
          end
          count += 1
          log(:info, "Cleaned stale #{state} session #{session.id}")
        rescue StandardError => e
          log(:warn, "Failed to clean session #{session.id}: #{e.message}")
        end
        count
      end

      # A reservation queued behind the concurrency cap, or waiting on cluster
      # capacity, is doing exactly what it is supposed to (AD-7, AD-8).
      def deliberately_waiting?(session)
        session.session_admission&.wait_reason.in?(SessionAdmission::WAIT_REASONS)
      end

      def unreleased_admission?(session)
        admission = session.session_admission
        admission.present? && admission.released_at.nil?
      end

      def stale_sessions_scope(state, threshold)
        scope = TerminalSession.where(state: state.to_s)

        case state
        when :not_started
          scope.where(created_at: ...threshold.ago)
        when :running
          scope.where(started_at: ...threshold.ago).or(
            TerminalSession
              .where(state: state.to_s, started_at: nil)
              .where(created_at: ...threshold.ago)
          )
        when :finishing
          scope.where(finishing_at: ...threshold.ago)
        else
          scope.where(started_at: ...threshold.ago)
        end
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
        session.start_finishing! if session.may_start_finishing?

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
        return unless session.temporal_workflow_id.present?

        TemporalService.cancel_workflow(session.workflow_id)
      rescue StandardError => e
        log(:warn, "Failed to cancel workflow for session #{session.id}: #{e.message}")
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
