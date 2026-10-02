# frozen_string_literal: true

module Chat
  # What a failure notice says, whichever messenger carries it.
  module RunFailure
    module_function

    # What actually went wrong: the quota case names itself, otherwise the last
    # failed step's message. Truncated — a container log dump in a chat thread
    # helps nobody, and the run page has the whole thing.
    def summary(run)
      if run.failure_reason == "quota_exceeded"
        return "#{run.failed_agent_credential&.agent_type || 'The connected account'} ran out of credits."
      end

      step = run.step_runs.where(state: "failed").order(:updated_at).last
      [ step&.step&.name, step&.error_message.to_s.truncate(400).presence ].compact.join(": ").presence ||
        run.failure_reason.to_s.humanize.presence
    end

    def url(run)
      return nil if run.project_id.blank?

      path = Rails.application.routes.url_helpers.company_project_workflow_run_path(run.project_id, run.id)
      "#{Settings.protocol}://#{Settings.domain}#{path}"
    end
  end
end
