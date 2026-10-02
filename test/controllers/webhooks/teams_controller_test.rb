# frozen_string_literal: true

require "test_helper"

class Webhooks::TeamsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    with_teams_enabled
    stub_bot_framework_keys!
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @integration = Integration.create!(provider: :teams, company: @company, connected_by: @user,
                                       name: "Contoso", status: :active,
                                       settings: { "tenant_id" => TEAMS_CUSTOMER_TENANT })
    @endpoint = create(:webhook_endpoint, slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}", provider: :teams,
                                          verification_strategy: :none, secret: nil, company: @company,
                                          config: { "integration_id" => @integration.id })
  end

  def deliver(activity, token: bot_framework_token)
    post teams_activities_webhook_path, params: activity.to_json,
                                        headers: { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }
  end

  test "a message that mentions the bot is accepted once and queued" do
    assert_enqueued_jobs(1, only: Webhooks::ProcessEventJob) do
      deliver(teams_activity)
      deliver(teams_activity)
    end

    assert_response :ok
    received = ReceivedWebhook.sole
    assert_equal @endpoint, received.webhook_endpoint
    assert_equal "19:abc@thread.tacv2;messageid=1700000000001:1700000000002", received.idempotency_key
  end

  test "an activity the Bot Framework did not sign for this bot is refused" do
    deliver(teams_activity, token: bot_framework_token(aud: "another-bot"))

    assert_response :unauthorized
    assert_equal 0, ReceivedWebhook.count
  end

  test "channel messages that do not mention the bot are dropped unstored, a typed @name included" do
    deliver(teams_activity(mention: false, text: "lunch?"))
    deliver(teams_activity(mention: false, text: "@Aixle Flow deploy"))

    assert_response :ok
    assert_equal 0, ReceivedWebhook.count
  end

  test "a 1:1 message needs no mention; a bot's own message is never taken" do
    deliver(teams_activity(conversation_type: "personal", mention: false))
    deliver(teams_activity(conversation_type: "personal", mention: false, id: "other",
                           from: { "id" => "28:#{TEAMS_APP_ID}" }))

    assert_equal 1, ReceivedWebhook.count
  end

  test "a tenant no company has connected is acknowledged and ignored" do
    @endpoint.update!(enabled: false)

    deliver(teams_activity)

    assert_response :ok
    assert_equal 0, ReceivedWebhook.count
  end

  test "being added to a team records the conversation and queues one welcome; removal is remembered" do
    added = teams_activity(mention: false, type: "installationUpdate", action: "add").except("text", "entities")

    assert_enqueued_with(job: Teams::WelcomeJob) { deliver(added) }
    conversation = ChatConversation.sole
    assert_equal [ "19:abc@thread.tacv2", "channel", "Onboarding", "19:team@thread.tacv2", TEAMS_SERVICE_URL ],
                 conversation.values_at(:external_id, :kind, :name, :team_external_id, :service_url)
    assert_equal 0, ReceivedWebhook.count

    deliver(added.merge("action" => "remove"))
    assert_not conversation.reload.installed?
  end

  test "an addressed message records the conversation it came from" do
    deliver(teams_activity)

    assert_equal "19:abc@thread.tacv2", ChatConversation.sole.external_id
  end

  test "a 1:1 file's download link is not stored" do
    activity = teams_activity(conversation_type: "personal", mention: false, attachments: [
      { "contentType" => "application/vnd.microsoft.teams.file.download.info", "name" => "brief.pdf",
        "content" => { "downloadUrl" => "https://contoso.sharepoint.com/secret-link", "uniqueId" => "u1", "fileType" => "pdf" } }
    ])

    deliver(activity)

    content = ReceivedWebhook.sole.raw_payload.dig("attachments", 0, "content")
    assert_equal({ "uniqueId" => "u1", "fileType" => "pdf" }, content)
  end
end
