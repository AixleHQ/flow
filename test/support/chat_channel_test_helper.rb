# frozen_string_literal: true

# A chat channel connected to a company, the way redeeming a connect code in
# the channel leaves it (Chat::ChannelConnect), for tests that need a chat
# trigger to listen somewhere. Reuses the company's install of that messenger,
# or creates an inactive one: listening needs no active install, and a test
# about connecting the messenger still finds it unconnected.
module ChatChannelTestHelper
  SLACK_CHANNEL = "C1"
  TEAMS_CHANNEL = "19:abc@thread.tacv2"

  module_function

  def connect_chat_channel(company:, provider: "slack", external_id: nil, integration: nil, name: nil, kind: "channel")
    provider = provider.to_s
    integration ||= Integration.where(company: company, provider: provider).order(:id).first ||
                    chat_integration(company, provider)
    conversation = ChatConversation.registry_row(integration, external_id || default_channel(provider))
    if conversation.new_record?
      conversation.assign_attributes(provider: provider, kind: kind, name: name)
      if provider == "teams"
        conversation.assign_attributes(service_url: TeamsTestHelper::TEAMS_SERVICE_URL,
                                       tenant_id: TeamsTestHelper::TEAMS_CUSTOMER_TENANT)
      end
      conversation.save!
    end
    ChatChannelConnection.find_or_create_by!(chat_conversation: conversation, company: company)
    conversation
  end

  def default_channel(provider) = provider.to_s == "teams" ? TEAMS_CHANNEL : SLACK_CHANNEL

  def chat_integration(company, provider)
    integration = Integration.new(company: company, provider: provider, status: :inactive, name: provider.capitalize,
                                  connected_by: company.users.first || User.first)
    if provider == "slack"
      integration.credentials_data = { "bot_token" => FakeSlackClient::DEFAULT_BOT_TOKEN,
                                       "bot_user_id" => FakeSlackClient::DEFAULT_BOT_USER,
                                       "team_id" => FakeSlackClient::DEFAULT_TEAM_ID }
      integration.settings = { "team_id" => FakeSlackClient::DEFAULT_TEAM_ID }
    else
      integration.settings = { "tenant_id" => TeamsTestHelper::TEAMS_CUSTOMER_TENANT }
    end
    integration.save!
    integration
  end
end
