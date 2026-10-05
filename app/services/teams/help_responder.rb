# frozen_string_literal: true

module Teams
  # Answers `help` (or a message no trigger matched) with what the conversation
  # can start. Best-effort: a Teams outage never fails the dispatch it came from.
  module HelpResponder
    module_function

    def call(event)
      data = event.data.to_h
      conversation = Notifier.conversation_for(data["integration_id"], data.dig("conversation", "id"))
      return false if conversation.nil?

      Notifier.post(conversation, text: catalog(Chat::HelpCatalog.bindings(event)),
                                  thread_id: data["thread_id"])
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
