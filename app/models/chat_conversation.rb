# frozen_string_literal: true

# A conversation the chat bot was added to or addressed in
# (docs/design/teams-integration.md §6.4). The service URL is only ever written
# from an authenticated activity, so a reference built from this row can only
# point a reply where Microsoft said the conversation lives.
class ChatConversation < ApplicationRecord
  extend Enumerize

  belongs_to :integration

  enumerize :kind, in: %i[channel group direct], predicates: true

  validates :provider, :external_id, presence: true

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

    row = find_or_initialize_by(integration: integration, external_id: external_id)
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

      row = find_or_initialize_by(integration_id: team_conversation.integration_id, external_id: channel["id"])
      row.update!(provider: "teams", kind: "channel", name: channel["name"].presence || row.name || "General",
                  tenant_id: team_conversation.tenant_id, team_external_id: team_conversation.team_external_id,
                  team_aad_group_id: team_conversation.team_aad_group_id, team_name: team_conversation.team_name,
                  service_url: team_conversation.service_url, installed: true)
    rescue ActiveRecord::RecordNotUnique
      retry
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
