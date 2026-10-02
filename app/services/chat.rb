# frozen_string_literal: true

# The messengers a workflow can be started from and answer in
# (docs/design/teams-integration.md §5). Every provider's message becomes one
# `chat.message` event, so triggers, run context and reporting read one shape
# whichever messenger it came from.
module Chat
  EVENT_TYPE = "chat.message"

  # Triggers saved before the messaging port keep their provider-named event
  # type and match that provider's messages only.
  LEGACY_EVENT_TYPES = { "slack.message" => "slack" }.freeze

  PROVIDERS = { "slack" => "Chat::SlackProvider", "teams" => "Chat::TeamsProvider" }.freeze

  # Answered before any trigger runs, so no trigger may claim it as its command.
  RESERVED_COMMAND = %r{\A/?help\z}i

  # Event data that routes a message rather than describing it.
  TRANSPORT_KEYS = %w[provider workspace conversation thread_id message_id actor].freeze

  module_function

  def event_types = [ EVENT_TYPE, *LEGACY_EVENT_TYPES.keys ]

  def event?(event) = event_types.include?(event&.event_type.to_s)

  # The trigger event types a message from this provider is matched against.
  def event_types_for(provider)
    [ EVENT_TYPE, *LEGACY_EVENT_TYPES.select { |_, key| key == provider.key }.keys ]
  end

  def provider(key)
    PROVIDERS[key.to_s]&.constantize
  end

  # The provider whose own receiver produced this event. A generic webhook
  # chooses its whole payload, so a provider named in the data counts only when
  # the event's source is that provider's receiver.
  def provider_for(event)
    return nil unless event?(event)

    key = LEGACY_EVENT_TYPES[event.event_type.to_s] || event.data.to_h["provider"].to_s
    key == event.source.to_s.split(":", 2).first ? provider(key) : nil
  end

  def help_request?(event)
    provider_for(event)&.help_request?(event) || false
  end

  def answer_help(event)
    provider_for(event)&.answer_help(event) || false
  end

  def run_context(event)
    provider_for(event)&.run_context(event) || {}
  end

  # Where a run came from, for a run started before the provider-neutral block
  # existed too: those carry only Slack's own block.
  def origin(run)
    context = run&.shared_context.to_h
    context["chat"].presence || SlackProvider.origin_from_legacy(context["slack"])
  end

  def origin_provider(run)
    provider(origin(run)&.dig("provider"))
  end
end
