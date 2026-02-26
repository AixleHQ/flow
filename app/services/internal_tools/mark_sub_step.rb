# frozen_string_literal: true

module InternalTools
  class MarkSubStep < Base
    ALLOWED_STATUSES = %w[in_progress completed skipped].freeze

    def execute
      require_workflow_context!

      ssr = step_run.sub_step_runs.find_by(id: params[:id])
      return error("Sub-step run #{params[:id]} not found in current step") unless ssr

      new_status = params[:status]
      return error("Invalid status '#{new_status}'. Allowed: #{ALLOWED_STATUSES.join(', ')}") unless new_status.in?(ALLOWED_STATUSES)

      ssr.state = new_status
      ssr.note = params[:note] if params.key?(:note)
      ssr.data = params[:data] if params.key?(:data)
      ssr.started_at = Time.current if new_status == "in_progress" && ssr.started_at.nil?
      ssr.completed_at = Time.current if %w[completed skipped].include?(new_status)
      ssr.save!

      success({
        id: ssr.id,
        status: ssr.state,
        note: ssr.note,
        data: ssr.data
      }.to_json)
    end
  end
end
