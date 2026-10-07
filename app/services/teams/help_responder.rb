# frozen_string_literal: true

module Teams
  # Answers `help` (or a message no trigger matched) with what the conversation
  # can start. Best-effort: a Teams outage never fails the dispatch it came from.
  module HelpResponder
    module_function

    PRIVATE_HINT = "Only you can see this. To start a workflow, mention Aixle Flow in the conversation, so " \
                   "everyone can follow the run. `/help` lists what this conversation can start."

    def call(event, hint: false)
      data = event.data.to_h
      conversation = Notifier.conversation_for(data["integration_id"], data.dig("conversation", "id"))
      return false if conversation.nil?

      text = hint ? PRIVATE_HINT : catalog(Chat::HelpCatalog.bindings(event))
      if data["targeted"]
        ConnectorClient.send_targeted(conversation.teams_reference(thread_id: data["thread_id"]),
                                      { type: "message", textFormat: "markdown", text: text },
                                      recipient: data["requester"], about: data["message_id"])
      else
        Notifier.post(conversation, text: text, thread_id: data["thread_id"])
      end
      true
    rescue StandardError => e
      Rails.logger.error("[Teams::HelpResponder] event ##{event&.id}: #{e.message}")
      false
    end

    def catalog(bindings)
      return "No triggers are set up for this conversation yet." if bindings.empty?

      lines = bindings.map do |binding|
        workflow = Chat::HelpCatalog.workflow_name(binding)
        label = Chat::HelpCatalog.label(binding)
        line = label == workflow ? "- **#{Notifier.escape(workflow)}**" : "- **#{Notifier.escape(label)}** — #{Notifier.escape(workflow)}"
        line += " (#{Notifier.escape(Chat::HelpCatalog.pattern(binding))})"
        binding.project&.name.present? ? "#{line} _#{Notifier.escape(binding.project.name)}_" : line
      end
      "**What this conversation can start**\n\n#{lines.join("\n")}"
    end
  end
end
