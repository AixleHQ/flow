# frozen_string_literal: true

require "test_helper"

# The chat channels connected to a project's company, and disconnecting one.
class Api::V1::Projects::ChatChannelsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = create(:company, name: "Acme")
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @slack = create(:integration, provider: :slack, status: :active, company: @company, project: nil)
    @slack.update!(credentials_data: { "bot_token" => "xoxb-acme" })
    @deploys = connect_chat_channel(company: @company, integration: @slack, external_id: "C0DEPLOYS1", name: "deploys")
    sign_in_as(@owner)
  end

  test "index lists the company's connected channels, by messenger, and nothing else" do
    teams = create(:integration, provider: :teams, status: :active, company: @company, project: nil)
    connect_chat_channel(company: @company, provider: "teams", integration: teams)
    ChatConversation.create!(integration: @slack, provider: "slack", external_id: "C0UNCONNE1", kind: "channel")
    connect_chat_channel(company: create(:company), external_id: "C0FOREIGN1")
    ChatChannelConnection.find_by!(chat_conversation: @deploys).update!(posted_by_external_id: "U0POSTER")

    get api_v1_project_chat_channels_path(@project), params: { provider: "slack" }, as: :json

    assert_response :success
    channels = response.parsed_body["channels"]
    assert_equal [ [ @deploys.id, "#deploys", "slack", nil ] ],
                 channels.map { |c| c.values_at("id", "label", "provider", "posted_by") }

    get api_v1_project_chat_channels_path(@project), as: :json
    assert_equal %w[slack teams], response.parsed_body["channels"].pluck("provider").sort
  end

  test "disconnecting a channel switches off the triggers listening there and tells the channel" do
    stub_slack_client!
    workflow = create(:workflow, scope: @project)
    trigger = create(:trigger_binding, project: @project, workflow: workflow, created_by: @owner, chat_channel: "C0DEPLOYS1")

    delete api_v1_project_chat_channel_path(@project, @deploys), as: :json
    assert_response :no_content
    perform_enqueued_jobs

    assert_not ChatChannelConnection.exists?(chat_conversation: @deploys, company: @company)
    trigger.reload
    assert_equal [ false, nil, { "provider" => "slack" } ], [ trigger.enabled, trigger.chat_conversation, trigger.filter_predicate ]
    assert_equal [ "C0DEPLOYS1", "*Acme* disconnected this channel." ], fake_slack.last_posted_message.values_at(:channel, :text)
  end

  test "a channel the company has not connected cannot be disconnected from here" do
    foreign = connect_chat_channel(company: create(:company), external_id: "C0FOREIGN1")

    delete api_v1_project_chat_channel_path(@project, foreign), as: :json

    assert_response :not_found
    assert ChatChannelConnection.exists?(chat_conversation: foreign)
  end
end
