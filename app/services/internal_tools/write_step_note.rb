# frozen_string_literal: true

module InternalTools
  class WriteStepNote < Base
    def execute
      require_workflow_context!

      return error("Note text is required") if params[:note].blank?

      existing = step_run.step_note
      new_note = if existing.present?
        "#{existing}\n---\n#{params[:note]}"
      else
        params[:note]
      end

      step_run.update!(step_note: new_note)
      step_run.broadcast_update!
      success("Note saved. Current note:\n#{new_note}")
    end
  end
end
