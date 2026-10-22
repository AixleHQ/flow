# frozen_string_literal: true

require "test_helper"

# Asking for a connect code and following what became of it.
class Api::V1::Projects::ChatConnectCodesTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, name: "Acme")
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @slack = create(:integration, provider: :slack, status: :active, company: @company, project: nil,
                                  settings: { "team_id" => "T1", "bot_name" => "aixle-flow" })
    @slack.update!(credentials_data: { "bot_token" => "xoxb-acme", "bot_user_id" => "U0BOT" })
    sign_in_as(@owner)
  end

  test "a code comes with what to post where, once; its state is followed until it is used" do
    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys" }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_match(/\Aconnect aixle-[0-9A-HJKMNP-TV-Z]{8}\z/, body["command"])
    assert_equal [ "pending", "#deploys", "aixle-flow", "@aixle-flow", "/invite @aixle-flow" ],
                 body.values_at("state", "channel_name", "bot_name", "mention", "invite")
    record = ChatConnectCode.find(body["id"])
    assert_equal [ @company, @owner ], [ record.company, record.requested_by ]
    assert_not_equal body["code"], record.code_digest

    conversation = connect_chat_channel(company: @company, integration: @slack, external_id: "C0DEPLOYS1", name: "deploys")
    record.update!(redeemed_at: Time.current, chat_channel_connection: conversation.chat_channel_connections.sole)
    get api_v1_project_chat_connect_code_path(@project, record), as: :json

    assert_response :success
    shown = response.parsed_body
    assert_equal [ "redeemed", "#deploys" ], [ shown["state"], shown.dig("channel", "label") ]
    assert_nil shown["code"]
  end

  test "Slack's bot name is its display name, read from the install once when it was never stored" do
    @slack.update!(settings: { "team_id" => "T1" })
    stub_slack_client!.bot_display_name = "Aixle Flow (staging)"

    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys" }, as: :json
    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys" }, as: :json

    assert_equal "@Aixle Flow (staging)", response.parsed_body["mention"]
    assert_equal 1, fake_slack.auth_tests.size
    assert_equal "Aixle Flow (staging)", @slack.reload.settings["bot_name"]
  end

  test "an install that may not read names offers the bot's username" do
    @slack.update!(settings: { "team_id" => "T1" })
    stub_slack_client!.user_info_error = "missing_scope"

    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys" }, as: :json

    assert_equal "@aixle-flow", response.parsed_body["mention"]
  end

  test "a code is always for a channel named up front" do
    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: " # " }, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "Name the channel to connect: its name, such as #deploys" ], response.parsed_body["errors"]
    assert_equal 0, ChatConnectCode.count
  end

  test "a messenger the company has not connected, or a trigger of another project, gets no code" do
    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "teams", channel: "Sales / General" }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "Connect Microsoft Teams on the Integrations page first" ], response.parsed_body["errors"]

    other = create(:project, company: @company, owner: @owner)
    trigger = create(:trigger_binding, project: other, workflow: create(:workflow, scope: other), created_by: @owner)
    post api_v1_project_chat_connect_codes_path(@project), params: { provider: "slack", channel: "#deploys", trigger_id: trigger.id }, as: :json
    assert_response :not_found
    assert_equal 0, ChatConnectCode.count
  end
end
