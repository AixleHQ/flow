# frozen_string_literal: true

# A conversation the chat bot was added to or addressed in
# (docs/design/teams-integration.md §6.4). The service URL is only ever written
# from an authenticated activity, so a reference built from this row can only
# point a reply where Microsoft said the conversation lives.
class ChatConversation < ApplicationRecord
  extend Enumerize

  # The install that first recorded the row. The row belongs to the workspace,
  # which every company that connected it shares.
  belongs_to :integration, optional: true
  belongs_to :chat_workspace, optional: true
  has_many :chat_channel_connections, dependent: :delete_all
  has_many :chat_messages, dependent: :delete_all

  enumerize :kind, in: %i[channel group direct], predicates: true

  validates :provider, :external_id, presence: true
  before_validation { self.chat_workspace_id ||= integration&.chat_workspace_id }

  scope :connected_to_company, ->(company_id) {
    where(id: ChatChannelConnection.where(company_id: company_id).select(:chat_conversation_id))
  }
  # The registry of the workspace an install serves: shared by every company
  # that connected it, so a row is never looked up by one company's install.
  # An install that serves no workspace yet keeps a registry of its own.
  scope :in_workspace_of, ->(integration_id) {
    workspaces = Integration.where(id: integration_id).where.not(chat_workspace_id: nil).select(:chat_workspace_id)
    where(chat_workspace_id: workspaces).or(where(chat_workspace_id: nil, integration_id: integration_id))
  }

  # The row for `external_id` in the workspace `integration` serves.
  def self.registry_row(integration, external_id)
    if integration.chat_workspace_id.nil?
      find_or_initialize_by(integration: integration, chat_workspace_id: nil, external_id: external_id)
    else
      find_or_initialize_by(chat_workspace_id: integration.chat_workspace_id, external_id: external_id) do |row|
        row.integration = integration
      end
    end
  end

  # A Slack channel the bot heard from. Slack keeps no registry of its own here,
  # so the row appears when the channel is connected.
  def self.record_slack!(integration:, channel_id:, name: nil)
    row = registry_row(integration, channel_id)
    row.assign_attributes(provider: "slack", kind: "channel", name: name.presence || row.name, last_activity_at: Time.current)
    row.save!
    row
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Whose bot posts here when no company is asking: any active install of the
  # workspace, since they all speak as the same bot.
  def posting_integration
    chat_workspace&.posting_integration || (integration if integration&.active?)
  end

  def label
    return name.presence || (group? ? "Group chat" : external_id) if provider == "teams"

    name.present? ? "##{name}" : external_id
  end

  # Upserts the conversation an authenticated Teams activity came from. A
  # channel event (created, renamed, deleted) arrives on the team's General
  # channel and names the channel it is about in channelData.
  def self.record_teams!(integration:, activity:)
    conversation = activity["conversation"].to_h
    channel_data = activity["channelData"].to_h
    external_id = conversation["id"].to_s.split(";messageid=", 2).first
    external_id = channel_data.dig("channel", "id") if conversation["conversationType"] == "channel" &&
                                                       channel_data.dig("channel", "id").present?
    return nil if external_id.blank?

    row = registry_row(integration, external_id)
    row.assign_attributes(
      provider: "teams",
      kind: Chat::TeamsProvider::CONVERSATION_TYPES.fetch(conversation["conversationType"].to_s, "group"),
      name: channel_data.dig("channel", "name").presence || row.name,
      tenant_id: channel_data.dig("tenant", "id") || conversation["tenantId"],
      team_external_id: channel_data.dig("team", "id") || row.team_external_id,
      team_name: channel_data.dig("team", "name").presence || row.team_name,
      service_url: activity["serviceUrl"],
      last_activity_at: Time.current
    )
    row.save!
    row
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # A team's channels as the Connector lists them, recorded beside the
  # conversation the app was installed in, so the trigger form can offer them
  # before anyone has addressed the bot there.
  def self.record_team_channels!(team_conversation, channels)
    channels.each do |channel|
      next if channel["id"].blank?

      row = sibling(team_conversation, channel["id"])
      row.update!(provider: "teams", kind: "channel", name: channel["name"].presence || row.name || "General",
                  tenant_id: team_conversation.tenant_id, team_external_id: team_conversation.team_external_id,
                  team_aad_group_id: team_conversation.team_aad_group_id, team_name: team_conversation.team_name,
                  service_url: team_conversation.service_url, installed: true)
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end

  # Another row in the same registry as `conversation`.
  def self.sibling(conversation, external_id)
    if conversation.chat_workspace_id
      find_or_initialize_by(chat_workspace_id: conversation.chat_workspace_id, external_id: external_id) do |row|
        row.integration_id = conversation.integration_id
      end
    else
      find_or_initialize_by(integration_id: conversation.integration_id, chat_workspace_id: nil, external_id: external_id)
    end
  end

  # What Teams::ConnectorClient needs to post here: in a channel, into the given
  # thread when there is one.
  def teams_reference(thread_id: nil, activity_id: nil)
    {
      "service_url" => service_url,
      "conversation_id" => thread_id.present? && channel? ? "#{external_id};messageid=#{thread_id}" : external_id,
      "activity_id" => activity_id,
      "tenant_id" => tenant_id,
      "bot" => { "id" => "28:#{Teams::Config.app_id}" }
    }.compact
  end
end
