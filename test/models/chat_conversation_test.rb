# frozen_string_literal: true

require "test_helper"

# The Teams conversation registry, fed activities shaped as Microsoft sends them:
# only the app's install and a team rename name the team; a channel created
# later and every message carry the team's id alone.
class ChatConversationTest < ActiveSupport::TestCase
  TEAM = "19:team@thread.tacv2"
  GROUP = "1b22f251-0000-4000-8000-000000000001"

  setup do
    user = create(:user, :with_company)
    @integration = Integration.create!(provider: :teams, company: user.companies.first, connected_by: user,
                                       name: "Contoso", status: :active)
  end

  def record(type, channel_data, conversation_id: TEAM)
    ChatConversation.record_teams!(integration: @integration, activity: {
      "type" => type, "serviceUrl" => TEAMS_SERVICE_URL,
      "conversation" => { "id" => conversation_id, "conversationType" => "channel", "tenantId" => TEAMS_CUSTOMER_TENANT },
      "channelData" => { "tenant" => { "id" => TEAMS_CUSTOMER_TENANT } }.merge(channel_data)
    })
  end

  def install
    record("installationUpdate", { "team" => { "id" => TEAM, "name" => "Sales", "aadGroupId" => GROUP } })
  end

  def create_channel(name)
    record("conversationUpdate", { "eventType" => "channelCreated", "team" => { "id" => TEAM },
                                   "channel" => { "id" => "19:#{name.downcase}@thread.tacv2", "name" => name } })
  end

  test "a channel created after the app joined its team is named with that team" do
    install
    create_channel("Launch")
    channel = record("message", { "team" => { "id" => TEAM }, "channel" => { "id" => "19:launch@thread.tacv2" } },
                     conversation_id: "19:launch@thread.tacv2;messageid=1700000000001")

    assert_equal [ "Launch", "Sales", GROUP ], channel.values_at(:name, :team_name, :team_aad_group_id)
    assert_equal "Sales", channel.reload.team_name
  end

  test "a team named after its channels were recorded, and renamed later, is named on every channel" do
    create_channel("Launch")
    create_channel("Ops")
    assert_equal [ nil ], ChatConversation.distinct.pluck(:team_name)

    install
    assert_equal [ "Sales" ], ChatConversation.distinct.pluck(:team_name)

    record("conversationUpdate", { "eventType" => "teamRenamed", "team" => { "id" => TEAM, "name" => "Revenue" } })
    assert_equal [ "Revenue" ], ChatConversation.distinct.pluck(:team_name)
    assert_equal [ GROUP ], ChatConversation.distinct.pluck(:team_aad_group_id)
  end

  test "another team's channels keep their own name" do
    install
    other = record("installationUpdate", { "team" => { "id" => "19:other@thread.tacv2", "name" => "Finance" } },
                   conversation_id: "19:other@thread.tacv2")

    record("conversationUpdate", { "eventType" => "teamRenamed", "team" => { "id" => TEAM, "name" => "Revenue" } })

    assert_equal "Finance", other.reload.team_name
  end
end
