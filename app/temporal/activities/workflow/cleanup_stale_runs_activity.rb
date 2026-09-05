# frozen_string_literal: true

module Activities
  module Workflow
    class CleanupStaleRunsActivity < ::Activities::Base
      # A run that has been running or paused for longer than this is assumed
      # to have lost its WorkflowExecutionWorkflow process. Sized to cover the
      # longest realistic single-step run without prematurely killing slow-but-live work.
      STALE_THRESHOLD = 4.hours

      def run(_input = nil)
        cleaned_running = cleanup_stale(:running)
        cleaned_paused  = cleanup_stale(:paused)
        { cleaned_running:, cleaned_paused: }
      end

      private

      def cleanup_stale(state)
        count = 0
        stale_runs_scope(state).find_each do |run|
          next if run.shared_context["session_admission"] == true
          next if SessionAdmission.joins(terminal_session: :step_run).where(step_runs: { workflow_run_id: run.id }).unreleased.exists?
          fail_active_sessions(run)
          run.update_column(:failure_reason, "stale_run")
          run.fail! if run.may_fail?
          count += 1
        rescue StandardError => e
          log(:warn, "Failed to clean WorkflowRun #{run.id}: #{e.message}")
        end
        count
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

      def stale_runs_scope(state)
        WorkflowRun.where(state: state.to_s)
                   .where(started_at: ...STALE_THRESHOLD.ago)
      end
    end
  end
end
