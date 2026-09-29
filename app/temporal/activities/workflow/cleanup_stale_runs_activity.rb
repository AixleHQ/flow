# frozen_string_literal: true

module Activities
  module Workflow
    # Settles runs whose WorkflowExecutionWorkflow is gone but whose row still
    # says running or paused — the parent was terminated, timed out, crashed on a
    # workflow task, or its history expired, and nothing wrote the final status.
    #
    # Liveness comes from Temporal, not from age. An age threshold (it was 4 hours
    # on started_at) failed long agent steps, approvals waiting over lunch and runs
    # that had queued for most of that time, while a run whose parent really died
    # sat "running" until the threshold came round. A RUNNING execution owns its
    # run — its execution timeout is the backstop for a wedged one — and a probe
    # that fails proves nothing.
    class CleanupStaleRunsActivity < ::Activities::Base
      # A run younger than this is not probed; one sweep is the soonest it could
      # have been orphaned and noticed anyway.
      PROBE_AFTER = 15.minutes
      GONE = %i[closed not_found].freeze

      def run(_input = nil)
        cleaned_running = cleanup_stale(:running)
        cleaned_paused  = cleanup_stale(:paused)
        { cleaned_running:, cleaned_paused: }
      end

      # Public for maintenance:cleanup_stale_runs, which previews before it acts.
      def orphaned_runs(state)
        candidates(state).to_a.select { |run| execution_gone?(run) }
      end

      private

      def cleanup_stale(state)
        count = 0
        orphaned_runs(state).each do |run|
          # It may have finished between the query and the probe.
          next unless run.reload.state == state.to_s

          reap(run)
          count += 1
        rescue StandardError => e
          log(:warn, "Failed to clean WorkflowRun #{run.id}: #{e.message}")
        end
        count
      end

      def execution_gone?(run)
        TemporalService.execution_state(run.execution_workflow_id).in?(GONE)
      end

      def reap(run)
        # The durable stop marker is what stops a queued child from being
        # admitted after the parent has been declared stale.
        mark_stopped(run)
        fail_active_sessions(run)
        run.update_column(:failure_reason, "stale_run")
        run.fail! if run.may_fail?
      end

      def mark_stopped(run)
        return if run.stop_requested_at

        SessionAdmissionService.transaction do
          run.lock!
          run.update!(stop_requested_at: run.stop_requested_at || Time.current)
        end
      end

      def fail_active_sessions(run)
        active_sessions = run.step_runs
                             .includes(:terminal_session)
                             .filter_map(&:terminal_session)
                             .select(&:may_fail?)
        active_sessions.each do |session|
          SessionService.fail_session(
            session: session,
            error_message: "Terminated by stale run reaper (WorkflowRun ##{run.id})"
          )
        rescue StandardError => e
          log(:warn, "Failed to terminate session #{session.id} for run #{run.id}: #{e.message}")
        end
      end

      def candidates(state)
        WorkflowRun.where(state: state.to_s).where(started_at: ...PROBE_AFTER.ago)
      end
    end
  end
end
