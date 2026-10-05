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

  test "a tenant no company has connected is told so at most daily, and nothing is stored" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @endpoint.update!(enabled: false)

    assert_enqueued_jobs(1, only: Teams::UnboundTenantHintJob) do
      deliver(teams_activity)
      deliver(teams_activity(text: "again"))
      deliver(teams_activity(mention: false, text: "chatter"))
    end

    assert_response :ok
    assert_equal 0, ReceivedWebhook.count + ChatConversation.count
    hint = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities/1700000000002")
           .with(body: hash_including("text" => /hasn't connected Aixle Flow yet/))
           .to_return(status: 201, body: { id: "1" }.to_json)
    stub_teams_token!
    perform_enqueued_jobs(only: Teams::UnboundTenantHintJob)
    assert_requested hint
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

  test "a channel event records the channel it names, not the General channel it arrives on" do
    created = teams_activity(mention: false, type: "conversationUpdate").except("text", "entities").deep_merge(
      "conversation" => { "id" => "19:general@thread.tacv2" },
      "channelData" => { "eventType" => "channelCreated", "channel" => { "id" => "19:new@thread.tacv2", "name" => "Launch" } }
    )

    deliver(created)
    deliver(created.deep_merge("channelData" => { "eventType" => "channelDeleted" }))

    channel = ChatConversation.sole
    assert_equal [ "19:new@thread.tacv2", "Launch", false ], channel.values_at(:external_id, :name, :installed)
  end

  test "an addressed message records the conversation it came from" do
    deliver(teams_activity)

    assert_equal "19:abc@thread.tacv2", ChatConversation.sole.external_id
  end

  test "accepting a file consent card queues the upload; a card from elsewhere does not" do
    direct = ChatConversation.record_teams!(integration: @integration, activity: teams_activity(conversation_type: "personal"))
    token = Teams::FileSender.consent_verifier.generate({ "asset_id" => 7, "conversation_id" => direct.id })
    invoke = teams_activity(conversation_type: "personal", mention: false, type: "invoke", name: "fileConsent/invoke",
                            replyToId: "card-1", value: { "action" => "accept", "context" => { "token" => token },
                                                          "uploadInfo" => { "uploadUrl" => "https://contoso-my.sharepoint.com/u" } })

    assert_enqueued_with(job: Teams::FileConsentJob,
                         args: [ direct.id, 7, { "uploadUrl" => "https://contoso-my.sharepoint.com/u" }, "card-1" ]) { deliver(invoke) }
    assert_response :ok

    elsewhere = invoke.deep_merge("conversation" => { "id" => "a:1other" })
    forged = invoke.deep_merge("value" => { "context" => { "token" => "forged" } })
    declined = invoke.deep_merge("value" => { "action" => "decline" })
    assert_no_enqueued_jobs(only: Teams::FileConsentJob) { [ elsewhere, forged, declined ].each { |a| deliver(a) } }
  end

  test "a 1:1 file's download link is kept only until the message is handled" do
    activity = teams_activity(conversation_type: "personal", mention: false, attachments: [
      { "contentType" => "application/vnd.microsoft.teams.file.download.info", "name" => "brief.pdf",
        "content" => { "downloadUrl" => "https://contoso.sharepoint.com/secret-link", "uniqueId" => "u1", "fileType" => "pdf" } }
    ])

    stub_teams_token!
    stub_request(:post, %r{\A#{Regexp.escape(TEAMS_SERVICE_URL)}v3/conversations/}).to_return(status: 201, body: { id: "1" }.to_json)
    deliver(activity)
    assert_equal "https://contoso.sharepoint.com/secret-link",
                 ReceivedWebhook.sole.raw_payload.dig("attachments", 0, "content", "downloadUrl")

    perform_enqueued_jobs(only: Webhooks::ProcessEventJob)

    content = ReceivedWebhook.sole.raw_payload.dig("attachments", 0, "content")
    assert_equal({ "uniqueId" => "u1", "fileType" => "pdf" }, content)
  end
end
