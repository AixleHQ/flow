# frozen_string_literal: true

require "test_helper"

class Chat::TeamsProviderTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
    @endpoint = create(:webhook_endpoint, slug: "teams-tenant-#{TEAMS_CUSTOMER_TENANT}", provider: :teams,
                                          verification_strategy: :none, secret: nil, company: @company,
                                          config: { "integration_id" => 42 })
  end

  def normalized(activity)
    Chat::TeamsProvider.normalize(@endpoint, activity)
  end

  test "a channel mention becomes the provider-neutral chat message" do
    result = normalized(teams_activity(text: "deploy  staging"))
    data = result[:data]

    assert_equal "chat.message", result[:event_type]
    assert_equal "teams", data["provider"]
    assert_equal({ "id" => TEAMS_CUSTOMER_TENANT }, data["workspace"])
    assert_equal({ "id" => "19:abc@thread.tacv2", "type" => "channel", "name" => "Onboarding",
                   "team" => { "id" => "19:team@thread.tacv2", "name" => "Sales" } }, data["conversation"])
    assert_equal "19:abc@thread.tacv2", data["channel"]
    assert_equal [ "1700000000001", "1700000000002" ], data.values_at("thread_id", "message_id")
    assert_equal "deploy staging", data["text"]
    assert_equal "<at>Aixle Flow</at> deploy  staging", data["raw_text"]
    assert_equal TEAMS_SERVICE_URL, data["service_url"]
    assert_equal 42, data["integration_id"]
  end

  test "a message links back to itself the way Teams documents deep links" do
    integration = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso", status: :active)
    @endpoint.update!(config: { "integration_id" => integration.id })
    integration.chat_conversations.create!(provider: "teams", external_id: "19:abc@thread.tacv2", kind: "channel",
                                           team_aad_group_id: "1b22f251-0000-4000-8000-000000000001")

    channel = URI.parse(normalized(teams_activity)[:data]["url"])
    chat = normalized(teams_activity(conversation_type: "groupChat").deep_merge("conversation" => { "id" => "19:chat@thread.v2" }))

    assert_equal "/l/message/19:abc@thread.tacv2/1700000000002", channel.path
    assert_equal({ "tenantId" => TEAMS_CUSTOMER_TENANT, "groupId" => "1b22f251-0000-4000-8000-000000000001",
                   "parentMessageId" => "1700000000001", "teamName" => "Sales", "channelName" => "Onboarding" },
                 Rack::Utils.parse_query(channel.query))
    assert_equal "https://teams.microsoft.com/l/message/19:chat@thread.v2/1700000000002?context=%7B%22contextType%22:%22chat%22%7D",
                 chat[:data]["url"]
    assert_nil normalized(teams_activity(conversation_type: "personal"))[:data]["url"]
  end

  test "a name typed by hand is not a mention and stays in the request" do
    activity = teams_activity(text: "deploy").merge("text" => "@Aixle Flow deploy", "entities" => [])

    assert_equal "@Aixle Flow deploy", normalized(activity)[:data]["text"]
  end

  test "chats have no threads; a 1:1 file's link travels apart from what describes it" do
    activity = teams_activity(conversation_type: "personal", mention: false, attachments: [
      { "contentType" => "application/vnd.microsoft.teams.file.download.info", "name" => "brief.pdf",
        "content" => { "uniqueId" => "u1", "fileType" => "pdf", "downloadUrl" => "https://contoso-my.sharepoint.com/d" } },
      { "contentType" => "text/html", "content" => "<p>hi</p>" }
    ])
    data = normalized(activity)[:data]

    assert_equal "direct", data.dig("conversation", "type")
    assert_nil data["thread_id"]
    assert_equal [ { "name" => "brief.pdf", "file_type" => "pdf", "unique_id" => "u1", "mimetype" => "application/pdf" } ],
                 data["files"]
    assert_equal [ { "kind" => "download", "url" => "https://contoso-my.sharepoint.com/d" } ], data["file_refs"]
    assert_nil Chat::TeamsProvider.scrub(data)["file_refs"]
  end

  test "the sender is recognised by the Entra object id a Microsoft sign-in stored, never by email" do
    microsoft = IdentityProvider.deployment!("microsoft")
    create(:user_identity, user: @user, identity_provider: microsoft, subject: "b130c271-0000-4000-8000-000000000001")
    create(:user_identity, user: create(:user), identity_provider: create(:identity_provider, company: @company),
                           subject: "b130c271-0000-4000-8000-000000000002")

    actor = normalized(teams_activity)[:data]["actor"]
    assert_equal({ "id" => "b130c271-0000-4000-8000-000000000001", "name" => "Olo Brockhouse",
                   "aixle_user_id" => @user.id }, actor)

    other = normalized(teams_activity(from: { "aadObjectId" => "b130c271-0000-4000-8000-000000000002" }))
    assert_nil other[:data].dig("actor", "aixle_user_id")
  end

  test "a Teams message starts a Teams chat trigger and leaves Slack's triggers alone" do
    chat = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                                    filter_predicate: { "provider" => "teams" })
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                             filter_predicate: { "provider" => "slack" })
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    received = ReceivedWebhook.create!(webhook_endpoint: @endpoint, idempotency_key: "k1", event_type: "teams",
                                       raw_payload: teams_activity)

    WorkflowService.expects(:enqueue).with(has_entries(
      shared_context: has_entries("chat" => has_entries("provider" => "teams", "text" => "<at>Aixle Flow</at> deploy"))
    )).once.returns(build(:workflow_run))

    Webhooks::ProcessEventJob.perform_now(received.id)

    assert_equal [ chat.id ], TriggerDispatch.pluck(:trigger_binding_id)
  end
end
