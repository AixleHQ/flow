# frozen_string_literal: true

require "test_helper"

class Teams::ConnectorClientTest < ActiveSupport::TestCase
  setup do
    with_teams_enabled
    stub_teams_token!
    @reference = {
      "service_url" => TEAMS_SERVICE_URL, "conversation_id" => "19:abc@thread.tacv2;messageid=1700000000001",
      "activity_id" => "1700000000002", "tenant_id" => TEAMS_CUSTOMER_TENANT,
      "bot" => { "id" => "28:#{TEAMS_APP_ID}", "name" => "Aixle Flow" }, "user" => { "id" => "29:user" }
    }
    @thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
  end

  test "a reply goes into the thread, from the bot, with both ids escaped" do
    stub = stub_request(:post, "#{@thread}/1700000000002")
      .with(headers: { "Authorization" => "Bearer bot-token" },
            body: hash_including("type" => "message", "text" => "On it",
                                 "from" => { "id" => "28:#{TEAMS_APP_ID}", "name" => "Aixle Flow" },
                                 "recipient" => { "id" => "29:user" },
                                 "conversation" => { "id" => "19:abc@thread.tacv2;messageid=1700000000001" }))
      .to_return(status: 201, body: { id: "1700000000003" }.to_json)

    assert_equal "1700000000003", Teams::ConnectorClient.reply(@reference, type: "message", text: "On it")["id"]
    assert_requested stub
  end

  test "an edit replaces the bot's own message in place" do
    stub = stub_request(:put, "#{@thread}/1700000000003")
      .with(body: hash_including("id" => "1700000000003", "text" => "Done"))
      .to_return(status: 200, body: { id: "1700000000003" }.to_json)

    Teams::ConnectorClient.update(@reference, "1700000000003", type: "message", text: "Done")
    assert_requested stub
  end

  test "a new thread is a new conversation whose first activity is the root" do
    stub = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations")
      .with(body: hash_including("isGroup" => true, "tenantId" => TEAMS_CUSTOMER_TENANT,
                                 "channelData" => { "channel" => { "id" => "19:abc@thread.tacv2" },
                                                    "tenant" => { "id" => TEAMS_CUSTOMER_TENANT } }))
      .to_return(status: 201, body: { id: "19:abc@thread.tacv2;messageid=1700000000009", activityId: "1700000000009" }.to_json)

    result = Teams::ConnectorClient.start_thread(@reference, channel_id: "19:abc@thread.tacv2",
                                                             activity: { type: "message", text: "Weekly report" })
    assert_equal "1700000000009", result["activityId"]
    assert_requested stub
  end

  test "a throttle is retried once; a refusal is an error with its status" do
    stub_request(:post, "#{@thread}/1700000000002")
      .to_return({ status: 429, headers: { "Retry-After" => "0" } }, { status: 201, body: { id: "x" }.to_json })
    assert_equal "x", Teams::ConnectorClient.reply(@reference, type: "message", text: "hi")["id"]

    stub_request(:post, "#{@thread}/1700000000002").to_return(status: 403, body: { error: { code: "BotNotInConversationRoster" } }.to_json)
    error = assert_raises(Teams::Error) { Teams::ConnectorClient.reply(@reference, type: "message", text: "hi") }
    assert_equal 403, error.status
    assert_match(/BotNotInConversationRoster/, error.message)
  end

  test "nothing is sent to a reply address outside the Bot Framework" do
    error = assert_raises(Teams::Error) do
      Teams::ConnectorClient.reply(@reference.merge("service_url" => "https://attacker.example/"), type: "message", text: "hi")
    end
    assert_match(/not a Bot Framework host/, error.message)
  end
end
