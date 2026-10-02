# frozen_string_literal: true

module Chat
  # What a conversation can start: the triggers a message from it would be
  # matched against, with the command each one answers to. Each messenger renders
  # it its own way.
  module HelpCatalog
    module_function

    def bindings(event, channel)
      TriggerBinding.for_event(event)
        .includes(:workflow, :project)
        .select { |binding| applies_to_channel?(binding, channel) }
        .sort_by { |binding| [ binding.project&.name.to_s, label(binding) ] }
    end

    def applies_to_channel?(binding, channel)
      predicate = binding.filter_predicate.to_h
      return true unless predicate.key?("channel")

      predicate["channel"].to_s == channel.to_s
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
