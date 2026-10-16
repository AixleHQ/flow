# frozen_string_literal: true

module InternalTools
  class GetStepResult < Base
    tool do
      display_name "Get Step Result"
      description "Recover a full step note or one sub-step's complete note and structured data. " \
                  "IDs must belong to the current workflow run. Use this when an initial-context preview is shortened."
      tags :workflow_control
      inject_when :workflow_step_session
      user_attachable false
      read_only
      param :step_run_id, type: :integer, description: "Step run ID from the context.", required: true
      param :sub_step_run_id, type: :integer, description: "Optional sub-step run ID to read its complete note/data."
    end

    def execute
      require_workflow_context!
      target = workflow_run.step_runs.find_by(id: params[:step_run_id])
      return error("Step run not found in the current workflow run") unless target

      payload = { step_run_id: target.id, step_id: target.step_id, state: target.state, note: target.step_note }
      if params[:sub_step_run_id].present?
        sub_run = target.sub_step_runs.includes(:sub_step).find_by(id: params[:sub_step_run_id])
        return error("Sub-step run not found in this step run") unless sub_run

        payload[:sub_step] = { id: sub_run.id, name: sub_run.sub_step.name, state: sub_run.state,
                               note: sub_run.note, data: sub_run.data }
      else
        payload[:sub_steps] = target.sub_step_runs.includes(:sub_step).order(:id).map do |sub_run|
          { id: sub_run.id, name: sub_run.sub_step.name, state: sub_run.state }
        end
      end
      success(payload.to_json)
    end
  end
end
