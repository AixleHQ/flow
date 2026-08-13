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
          run.update_column(:failure_reason, "stale_run")
          run.fail! if run.may_fail?
          count += 1
        rescue StandardError => e
          log(:warn, "Failed to clean WorkflowRun #{run.id}: #{e.message}")
        end
        count
      end

      def stale_runs_scope(state)
        WorkflowRun.where(state: state.to_s)
                   .where(started_at: ...STALE_THRESHOLD.ago)
      end
    end
  end
end
