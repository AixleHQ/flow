# frozen_string_literal: true

module Chat
  # What a conversation can start: the triggers a message from it would be
  # matched against, with the command each one answers to. Each messenger renders
  # it its own way.
  module HelpCatalog
    module_function

    # Every condition but the text is about where the message came from — the
    # messenger, the channel, direct or not — so those decide what is listed here.
    def bindings(event)
      data = event.data.to_h
      TriggerBinding.for_event(event)
        .includes(:workflow, :project)
        .select { |binding| TriggerFilter.match?(binding.filter_predicate.to_h.except("text"), data) }
        .sort_by { |binding| [ binding.project&.name.to_s, label(binding) ] }
    end

    def label(binding)
      command(binding).presence || workflow_name(binding)
    end

    def workflow_name(binding)
      binding.workflow&.name.presence || "workflow"
    end

    def command(binding)
      text = binding.filter_predicate.to_h["text"]
      return nil if text.blank?

      text.is_a?(Hash) ? text["value"].presence : text.to_s.presence
    end

    def pattern(binding)
      text = binding.filter_predicate.to_h["text"]
      return "any message" if text.blank?

      if text.is_a?(Hash)
        return "any message" if text["value"].blank?

        "#{text['op'].presence || 'contains'} \"#{text['value']}\""
      else
        "contains \"#{text}\""
      end
    end
  end
end
