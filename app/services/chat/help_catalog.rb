# frozen_string_literal: true

module Chat
  # What a conversation can start: the triggers a message from it would be
  # matched against, with the command each one answers to. Each messenger renders
  # it its own way.
  module HelpCatalog
    module_function

    # The triggers listening in the conversation, in every company that
    # connected it: their connection was announced there, so listing them tells
    # nobody anything new. Conditions other than the text (the sender, say)
    # still decide what is listed.
    def bindings(event)
      return [] if Chat.provider_for(event).nil?

      data = event.data.to_h
      TriggerBinding.active.where(event_type: event.event_type, project_id: listening_projects(data).select(:id))
        .joins(:workflow).merge(Workflow.active).merge(TriggerBinding.listening_in(event))
        .includes(:workflow, project: :company)
        .select { |binding| TriggerFilter.match?(binding.filter_predicate.to_h.except("text", "channel"), data) }
        .sort_by { |binding| [ binding.project&.company&.name.to_s, label(binding) ] }
    end

    def listening_projects(data)
      installs = Integration.find_by(id: data["integration_id"])&.chat_peers&.active
      Project.where(company_id: installs ? installs.select(:company_id) : [])
    end

    # Whose a listed trigger is, when the list spans several companies. Never
    # its project: the channel may hold guests and other organizations.
    def place(binding, bindings)
      return nil if bindings.map { |b| b.project&.company_id }.uniq.size < 2

      binding.project&.company&.name
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
