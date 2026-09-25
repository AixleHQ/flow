# frozen_string_literal: true

module Activities
  module ToolResults
    # A tool result's payload is whatever the tool printed, secrets included, so
    # it is kept for TOOL_RESULTS_RETENTION_DAYS and no longer.
    class CleanupActivity < Base
      # Twice ToolStrategy::MAX_TIMEOUT, the longest a tool may execute.
      STUCK_THRESHOLD = 60.minutes
      # One run's share of a backlog; the next run takes the rest.
      EXPIRE_PER_RUN = 5_000

      def run(_input = nil)
        retention = (Settings.tool_results&.retention_days || 30).to_i.days
        { expired: expire_stale_results(retention), failed_stuck: fail_stuck_processing }
      end

      private

      def expire_stale_results(retention)
        expired = 0
        ::ToolResult.stale(retention).limit(EXPIRE_PER_RUN).find_each do |result|
          expire(result)
          expired += 1
        rescue StandardError => e
          log(:warn, "Could not expire tool result #{result.execution_id}: #{e.message}")
        end
        expired
      end

      def expire(result)
        result.stdout_attacher.destroy if result.stdout
        result.stderr_attacher.destroy if result.stderr
        result.result_data_attacher.destroy if result.result_data
        result.output_attacher.destroy if result.output

        result.update!(state: "expired", stdout_data: nil, stderr_data: nil, result_data_data: nil, output_data: nil)
      end

      def fail_stuck_processing
        stuck = ::ToolResult.where(state: "processing").where(created_at: ...STUCK_THRESHOLD.ago)
        ids = stuck.pluck(:execution_id)
        return 0 if ids.empty?

        log(:warn, "Failing #{ids.size} stuck results: #{ids.join(', ')}")
        stuck.update_all(state: "failed", error: "Timed out: stuck in processing", updated_at: Time.current)
      end
    end
  end
end
