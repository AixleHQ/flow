# frozen_string_literal: true

module Teams
  # Chat::StatusCard as an Adaptive Card, posted into the thread a request came
  # from and edited there. A throttle or an outage is the caller's to retry; a
  # conversation the bot has left is dropped.
  module StatusCard
    STATES = {
      "accepted" => [ "⏳", "Accepted", "Default" ],
      "running" => [ "▶️", "Running", "Accent" ],
      "completed" => [ "✅", "Completed", "Good" ],
      "failed" => [ "❌", "Failed", "Attention" ],
      "cancelled" => [ "⏹️", "Cancelled", "Default" ],
      "skipped" => [ "⏭️", "Not started", "Warning" ]
    }.freeze

    module_function

    def post(event, status)
      reference = reference(event)
      return nil if reference.nil?

      Teams::ConnectorClient.send_message(reference, activity(status))["id"]
    rescue Teams::Error => e
      dropped(e)
    end

    def update(event, message_id, status)
      reference = reference(event)
      return nil if reference.nil?

      Teams::ConnectorClient.update(reference, message_id, activity(status))
      message_id
    rescue Teams::Error => e
      dropped(e)
    end

    def activity(status)
      { type: "message", summary: headline(status),
        attachments: [ { contentType: "application/vnd.microsoft.card.adaptive", content: card(status) } ] }
    end

    def card(status)
      icon, label, color = STATES.fetch(status.state)
      body = [
        { type: "TextBlock", text: "#{icon} #{label} — #{status.workflow}#{" · run ##{status.run_id}" if status.run_id}",
          weight: "Bolder", color: color, wrap: true },
        ({ type: "TextBlock", text: "Started by #{status.started_by}", isSubtle: true, spacing: "None", wrap: true } if status.started_by),
        ({ type: "TextBlock", text: "Since {{TIME(#{status.since.utc.iso8601})}}", isSubtle: true, spacing: "None" } if status.since),
        ({ type: "TextBlock", text: "Took #{status.duration}", isSubtle: true, spacing: "None" } if status.duration),
        ({ type: "TextBlock", text: status.detail.to_s.truncate(400), wrap: true } if status.detail.present?)
      ].compact
      actions = status.url ? [ { type: "Action.OpenUrl", title: "Open run", url: status.url } ] : []
      { "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: "1.5",
        body: body, actions: actions }
    end

    def headline(status)
      "#{STATES.fetch(status.state)[1]}: #{status.workflow}"
    end

    def reference(event)
      data = event.data.to_h
      conversation = Notifier.conversation_for(data["integration_id"], data.dig("conversation", "id"))
      return nil unless conversation&.installed?

      conversation.teams_reference(thread_id: data["thread_id"])
    end

    def dropped(error)
      raise Triggers::ReportToOriginJob::Retryable, error.message if error.retryable?

      Rails.logger.error("[Teams::StatusCard] #{error.message}")
      nil
    end
  end
end
