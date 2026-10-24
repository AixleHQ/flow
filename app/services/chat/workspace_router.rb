# frozen_string_literal: true

module Chat
  # A chat message's way from its workspace to the companies that connected the
  # channel it came from (docs/design/shared-chat-workspaces.md §10). What
  # concerns the workspace as a whole — a connect code, help, a command, a
  # private message — is answered once, by whichever install heard it. Then each
  # company with a trigger the message matches gets an event of its own, so the
  # message is stored only inside the companies it reached.
  module WorkspaceRouter
    module_function

    # The events published, one per company.
    def call(endpoint:, normalized:, source:, dedup_key:)
      heard_by = endpoint.chat_install
      return [] if heard_by.nil?

      event = event_for(heard_by, normalized, source)
      return [] if answered_once?(event)

      published = heard_by.chat_peers.active.includes(:company).filter_map do |install|
        publish_for(install, event, source, dedup_key)
      end
      Chat.answer_help(event) if published.empty?
      published
    end

    def event_for(install, normalized, source)
      TriggerEvent.new(event_type: normalized[:event_type], source: source, subject: normalized[:subject]&.to_s,
                       data: normalized[:data].deep_stringify_keys.merge("integration_id" => install.id),
                       company_id: install.company_id, occurred_at: Time.current)
    end

    def answered_once?(event)
      if Chat.connect_request?(event)
        Chat.answer_connect(event)
      elsif Chat.help_request?(event)
        Chat.answer_help(event)
      elsif Chat.answer_command(event)
        true
      elsif Chat.private_request?(event)
        Chat.answer_private(event)
      else
        return false
      end
      true
    end

    # The company's own copy of the event, published only when one of its
    # triggers matches it.
    def publish_for(install, event, source, dedup_key)
      own = event_for(install, { event_type: event.event_type, subject: event.subject, data: event.data }, source)
      return nil unless TriggerBinding.for_event(own).any? { |binding| binding.matches?(own.data) }

      TriggerEngine.publish(event_type: own.event_type, source: source, subject: own.subject, data: own.data,
                            company: install.company, dedup_key: "#{dedup_key}:c#{install.company_id}")
    end
  end
end
