# frozen_string_literal: true

class ToolResultCleanupJob
  STUCK_THRESHOLD = 60.minutes

  def perform
    retention = (Settings.tool_results&.retention_days || 30).days

    expire_stale_results(retention)
    fail_stuck_processing
  end

  private

  def expire_stale_results(retention)
    ToolResult.stale(retention).find_each do |tr|
      tr.stdout_attacher.destroy if tr.stdout
      tr.stderr_attacher.destroy if tr.stderr
      tr.result_data_attacher.destroy if tr.result_data
      tr.output_attacher.destroy if tr.output

      tr.update!(
        state: "expired",
        stdout_data: nil,
        stderr_data: nil,
        result_data_data: nil,
        output_data: nil
      )
    end
  end

  def fail_stuck_processing
    stuck = ToolResult.where(state: "processing")
                      .where("created_at < ?", STUCK_THRESHOLD.ago)
    return if stuck.empty?

    ids = stuck.pluck(:execution_id)
    Rails.logger.warn("[ToolResultCleanup] Failing #{ids.size} stuck results: #{ids.join(', ')}")

    stuck.update_all(state: "failed", error: "Timed out: stuck in processing", updated_at: Time.current)
  end
end
