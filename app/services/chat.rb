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

  # Answered before any trigger runs, so no trigger may claim them as its command.
  RESERVED_COMMAND = %r{\A/?(?:help|connect)\z}i

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

  # `connect <code>`: answered before help and before any trigger (Chat::ChannelConnect).
  def connect_request?(event)
    provider_for(event).present? && ChannelConnect.request?(event)
  end

  def answer_connect(event)
    ChannelConnect.call(event)
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
  # connected, and the channels connected to the company in each.
  def trigger_options(project)
    integrations = Integration.active.visible_for_project(project).where(provider: PROVIDERS.keys).to_a
    known = ChannelAccess.channels(project).group_by(&:provider)
    integrations.map { |integration| integration.provider.to_s }.uniq.sort.map do |key|
      { key: key, label: provider(key).label, bot_name: bot_name(key, project, fetch: false),
        conversations: Array(known[key]).map { |row| ChannelAccess.describe(row) } }
    end
  end

  # The name people type to mention the bot, for instructions shown in Aixle.
  # Slack's comes from the install (auth.test), read once and kept; Teams' is the
  # app's. `fetch: false` never calls Slack, for a page render.
  def bot_name(key, project, fetch: true)
    return Teams::AppPackage::NAME if key.to_s == TeamsProvider::KEY

    integration = Slack::InstallResolver.call(company_id: project.company_id, project_id: project.id)
    return nil if integration.nil?

    integration.settings.to_h["bot_name"].presence || (remember_slack_bot_name(integration) if fetch)
  end

  def remember_slack_bot_name(integration)
    name = Slack::Client.auth_test(token: integration.credentials_data["bot_token"])["user"].presence
    integration.update_column(:settings, integration.settings.to_h.merge("bot_name" => name)) if name
    name
  rescue Slack::Client::Error => e
    Rails.logger.warn("[Chat] auth.test failed for integration ##{integration.id}: #{e.message}")
    nil
  end

  def origin(run) = run&.shared_context.to_h["chat"].presence

  def origin_provider(run)
    provider(origin(run)&.dig("provider"))
  end
end
