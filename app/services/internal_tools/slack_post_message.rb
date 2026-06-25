# frozen_string_literal: true

module InternalTools
  # Platform tool: let a workflow agent post a message to Slack. Gated on the
  # project having an active Slack integration (errors clearly if not). Defaults
  # the channel/thread to the message that triggered the run, so a Slack-started
  # run can reply in-thread with just `text`.
  class SlackPostMessage < Base
    def execute
      require_workflow_context!
      return error("text is required") if params[:text].blank?

      integration = slack_integration
      return error("Slack is not connected for this project") if integration.nil?

      channel = params[:channel].presence || slack_context["channel"]
      return error("No channel given, and this run was not triggered from Slack") if channel.blank?

      thread_ts = params[:thread_ts].presence || slack_context["thread_ts"]
      posted = Slack::Notifier.post(
        integration: integration, channel: channel, text: params[:text].to_s, thread_ts: thread_ts
      )
      posted ? success("Posted to #{channel}") : error("Failed to post message to Slack")
    end

    private

    def slack_context
      workflow_run&.shared_context.to_h["slack"] || {}
    end

    # Prefer a project-scoped Slack install, falling back to a company-wide one.
    def slack_integration
      return nil if project.nil?

      Integration.active.where(provider: :slack)
        .where("(project_id = :pid) OR (project_id IS NULL AND company_id = :cid)",
               pid: project.id, cid: project.company_id)
        .order(Arel.sql("project_id IS NULL")) # project-scoped (false) sorts before company-wide
        .first
    end
  end
end
