# frozen_string_literal: true

module WorkflowTriggers
  # How a trigger reads wherever one is listed: the triggers API, the personal
  # MCP and the project's Triggers page all describe the same trigger the same
  # way. Two record kinds behind one shape:
  #   column                                       → ColumnWorkflowBinding
  #   slack / schedule / webhook / event / tracker → TriggerBinding
  class Serializer
    # The chat a message trigger listens to, by event type. A new messenger is
    # one more entry; `kind` stays the provider's form name for compatibility.
    CHAT_PROVIDERS = { TriggerBinding::SLACK_EVENT_TYPE => "slack" }.freeze

    def self.kind(event_type)
      case event_type
      when TriggerBinding::SLACK_EVENT_TYPE then "slack"
      when TriggerBinding::SCHEDULE_EVENT_TYPE then "schedule"
      when /\Awebhook\./ then "webhook"
      when /\Atracker\./ then "tracker"
      else "event"
      end
    end

    # What starts the run, for grouping: board, chat, schedule, webhook, tracker or event.
    def self.source(event_type)
      return "chat" if CHAT_PROVIDERS.key?(event_type.to_s)

      kind(event_type)
    end

    def self.webhook_url(slug)
      "https://#{Settings.domain}/webhooks/in/#{slug}"
    end

    # `webhook_endpoints` is { event_type => WebhookEndpoint } for the webhook
    # bindings being serialized, so a list asks for them once (see .endpoints_for).
    def initialize(webhook_endpoints: {})
      @webhook_endpoints = webhook_endpoints
    end

    # The endpoints behind the webhook bindings among `bindings`, keyed by event type.
    def self.endpoints_for(bindings)
      event_types = bindings.map(&:event_type).grep(/\Awebhook\./)
      return {} if event_types.empty?

      WebhookEndpoint.where(project_id: bindings.map(&:project_id).uniq)
                     .where("config ->> 'event_type' IN (?)", event_types)
                     .index_by { |endpoint| endpoint.config.to_h["event_type"] }
    end

    def column(binding)
      {
        id: binding.id,
        kind: "column",
        source: "board",
        event_type: "board.column_changed",
        board_column_id: binding.board_column_id,
        column_name: binding.board_column.name,
        trigger_mode: binding.trigger_mode,
        cooldown_seconds: binding.cooldown_seconds,
        created_by: creator(binding.created_by),
        # A column binding cannot be switched off; removing it is how it stops.
        enabled: true,
        **workflow(binding.workflow)
      }
    end

    def binding(binding)
      endpoint = @webhook_endpoints[binding.event_type]
      {
        id: binding.id,
        kind: self.class.kind(binding.event_type),
        source: self.class.source(binding.event_type),
        chat_provider: CHAT_PROVIDERS[binding.event_type],
        event_type: binding.event_type,
        name: binding.name,
        filter_predicate: binding.filter_predicate,
        trigger_mode: binding.trigger_mode,
        subject_policy: binding.subject_policy,
        subject_column_id: binding.subject_column_id,
        subject_title_template: binding.subject_title_template,
        schedule_config: binding.schedule_config,
        cooldown_seconds: binding.cooldown_seconds,
        notify_on_failure: binding.notify_on_failure,
        project_tracker_id: binding.project_tracker_id,
        aixle_changes: binding.aixle_changes,
        verification_strategy: endpoint&.verification_strategy&.to_s,
        webhook_url: endpoint && self.class.webhook_url(endpoint.slug),
        created_by: creator(binding.created_by),
        enabled: binding.enabled,
        **workflow(binding.workflow)
      }
    end

    private

    # Who a trigger runs as. nil for rows created before the creator was
    # recorded (and for a deleted account, whose reference is nullified) — the
    # UI shows those as "Unknown" and an unattended fire is skipped.
    def creator(user)
      return nil unless user

      { id: user.id, name: user.name }
    end

    def workflow(workflow)
      { workflow_id: workflow&.id, workflow_name: workflow&.name }
    end
  end
end
