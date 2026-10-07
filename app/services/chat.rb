# frozen_string_literal: true

# The messengers a workflow can be started from and answer in
# (docs/design/teams-integration.md §5). Every provider's message becomes one
# `chat.message` event, so triggers, run context and reporting read one shape
# whichever messenger it came from.
module Chat
  EVENT_TYPE = "chat.message"

  PROVIDERS = { "slack" => "Chat::SlackProvider", "teams" => "Chat::TeamsProvider" }.freeze

  # A dispatch started by a person's own action in the messenger (a message
  # action, /run), not by a trigger. Its run is followed by a status card.
  ACTION_SOURCE = "chat_action"

  # A tool that works through whichever messenger is connected requires this,
  # as tracker tools require Trackers::CAPABILITY.
  CAPABILITY = "chat"

  # Answered before any trigger runs, so no trigger may claim it as its command.
  RESERVED_COMMAND = %r{\A/?help\z}i

  # Event data that routes a message rather than describing it.
  TRANSPORT_KEYS = %w[provider workspace conversation thread_id message_id actor file_refs url targeted requester].freeze

  module_function

  def event?(event) = event&.event_type.to_s == EVENT_TYPE

  def provider(key)
    PROVIDERS[key.to_s]&.constantize
  end

  # The provider whose own receiver produced this event. A generic webhook
  # chooses its whole payload, so a provider named in the data counts only when
  # the event's source is that provider's receiver.
  def provider_for(event)
    return nil unless event?(event)

    key = event.data.to_h["provider"].to_s
    key == event.source.to_s.split(":", 2).first ? provider(key) : nil
  end

  def help_request?(event)
    provider_for(event)&.help_request?(event) || false
  end

  def answer_help(event)
    provider_for(event)&.answer_help(event) || false
  end

  def private_request?(event)
    provider_for(event)&.private_request?(event) || false
  end

  def answer_private(event)
    provider_for(event)&.answer_private(event) || false
  end

  # A command the messenger answers itself (Teams' run and status): true once answered.
  def answer_command(event)
    provider_for(event)&.answer_command(event) || false
  end

  def run_context(event)
    provider_for(event)&.run_context(event) || {}
  end

  # What the trigger form offers: the messengers the project's company has
  # connected, and the conversations each one's bot knows by name. Direct chats
  # are one person's each, so the form offers them as a kind, not one by one.
  def trigger_options(project)
    integrations = Integration.active.visible_for_project(project).where(provider: PROVIDERS.keys).to_a
    known = ChatConversation.where(integration: integrations).where.not(kind: "direct")
                            .order(:team_name, :name).group_by(&:provider)
    integrations.map { |integration| integration.provider.to_s }.uniq.sort.map do |key|
      { key: key, label: provider(key).label,
        conversations: Array(known[key]).map do |row|
          { id: row.external_id, name: row.name, kind: row.kind.to_s, team_name: row.team_name }
        end }
    end
  end

  def origin(run) = run&.shared_context.to_h["chat"].presence

  def origin_provider(run)
    provider(origin(run)&.dig("provider"))
  end
end
