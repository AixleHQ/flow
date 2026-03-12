# frozen_string_literal: true

module InternalTools
  class FinishSession < Base
    def execute
      unless session.mode == "non_interactive"
        return error("finish_session is only available in non-interactive sessions")
      end

      unless session.may_finish?
        return error("Session cannot be finished in current state: #{session.state}")
      end

      if params[:note].present? && step_run.present?
        append_step_note(params[:note])
      end

      SessionService.finish(session: session)
      success("Session finished successfully.")
    end

    private

    def append_step_note(text)
      existing = step_run.step_note
      new_note = existing.present? ? "#{existing}\n---\n#{text}" : text
      step_run.update!(step_note: new_note)
      step_run.broadcast_update!
    end
  end
end
