# frozen_string_literal: true

module InternalTools
  class FailSession < Base
    tool do
      display_name "Fail Session"
      description "Signal that a non-interactive session has failed. This terminates the session with an error. Use when the task cannot be completed."
      tags :session_lifecycle
      inject_when :non_interactive_session
      input_schema({
        type: "object",
        required: %w[reason],
        properties: {
          note: {
            type: "string",
            description: "Optional note with details (saved to step if in workflow context)"
          },
          reason: {
            type: "string",
            description: "Why the session failed"
          }
        }
      })
    end

    def execute
      unless session.mode == "non_interactive"
        return error("fail_session is only available in non-interactive sessions")
      end

      unless session.may_start_finishing? || session.finishing?
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
    end
  end
end
