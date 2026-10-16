# frozen_string_literal: true

module InternalTools
  class FinishSession < Base
    tool do
      display_name "Finish Session"
      description "Signal successful completion of a non-interactive session. This terminates the session. Call only after ALL work is done and output files are saved."
      tags :session_lifecycle
      inject_when :non_interactive_session
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {
          evidence_execution_ids: {
            type: "array",
            items: { type: "string", maxLength: 128 },
            maxItems: 20,
            description: "Successful recorded tool execution IDs from this session. Required when completion_evidence_required is enabled."
          },
          note: {
            type: "string",
            description: "Optional final note (saved to step if in workflow context)"
          }
        }
      })
    end

    def execute
      unless session.mode == "non_interactive"
        return error("finish_session is only available in non-interactive sessions")
      end

      unless session.may_start_finishing? || session.finishing?
        return error("Session cannot be finished in current state: #{session.state}")
      end

      evidence = CompletionEvidence.new(session).validate(params[:evidence_execution_ids])
      return error(evidence.errors.join("; ")) unless evidence.valid?

      if evidence.receipts.any?
        session.with_lock do
          session.update!(metadata: session.metadata.to_h.merge("completion_evidence" => evidence.receipts))
        end
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
    end
  end
end
