# frozen_string_literal: true

module InternalTools
  # Platform tool: let a workflow agent send a Slack message. Text and files are
  # both optional, but at least one is required — text only, files only, or both
  # arrive as a SINGLE Slack message. Gated on the project having an active Slack
  # integration. Defaults the channel/thread to the message that triggered the run.
  class SlackPostMessage < Base
    def execute
      require_workflow_context!
      files = normalized_files
      return error("Provide `text` and/or `files`") if params[:text].blank? && files.empty?

      integration = slack_integration
      return error("Slack is not connected for this project") if integration.nil?

      channel = params[:channel].presence || slack_context["channel"]
      return error("No channel given, and this run was not triggered from Slack") if channel.blank?

      thread_ts = params[:thread_ts].presence || slack_context["thread_ts"]
      sent = Slack::Notifier.post(
        integration: integration, channel: channel,
        text: params[:text].presence, files: files.presence, thread_ts: thread_ts
      )
      sent ? success("Sent to #{channel}") : error("Failed to send to Slack")
    end

    private

    # Coerce the files param (array of hashes, string- or symbol-keyed) into the
    # shape Slack::Client.upload_files expects; drop entries missing filename/content.
    def normalized_files
      Array(params[:files]).filter_map do |raw|
        f = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : {}
        next if f[:filename].to_s.empty? || f[:content].to_s.empty?

        { filename: f[:filename].to_s, content: f[:content].to_s, title: f[:title].presence }
      end
    end

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
