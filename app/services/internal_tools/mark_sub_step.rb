# frozen_string_literal: true

module InternalTools
  class MarkSubStep < Base
    tool do
      display_name "Mark Sub-Step"
      description "Update sub-step status with optional note and structured data. Only available during workflow execution."
      tags :workflow_control
      inject_when :workflow_step_session
      user_attachable false
      input_schema({
        type: "object",
        required: %w[id status],
        properties: {
          id: {
            type: "integer",
            description: "Sub-step run ID"
          },
          data: {
            type: "object",
            description: "Structured data — decisions, metrics, findings"
          },
          note: {
            type: "string",
            description: "What was done, decisions made"
          },
          status: {
            enum: %w[in_progress completed skipped],
            type: "string",
            description: "New status"
          }
        }
      })
    end

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
