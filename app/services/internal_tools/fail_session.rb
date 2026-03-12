# frozen_string_literal: true

module InternalTools
  class FailSession < Base
    def execute
      unless session.mode == "non_interactive"
        return error("fail_session is only available in non-interactive sessions")
      end

      unless session.may_finish?
        return error("Session cannot be finished in current state: #{session.state}")
      end

      reason = params[:reason].presence || "Session failed (no reason provided)"

      if params[:note].present? && step_run.present?
        append_step_note(params[:note])
      end

      step_run&.update!(error_message: reason)
      SessionService.finish(session: session)
      success("Session marked as failed: #{reason}")
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
