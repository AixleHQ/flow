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

  test "a name typed by hand is not a mention and stays in the request" do
    activity = teams_activity(text: "deploy").merge("text" => "@Aixle Flow deploy", "entities" => [])

    assert_equal "@Aixle Flow deploy", normalized(activity)[:data]["text"]
  end

  test "chats have no threads; a 1:1 file arrives as metadata only" do
    activity = teams_activity(conversation_type: "personal", mention: false, attachments: [
      { "contentType" => "application/vnd.microsoft.teams.file.download.info", "name" => "brief.pdf",
        "content" => { "uniqueId" => "u1", "fileType" => "pdf" } },
      { "contentType" => "text/html", "content" => "<p>hi</p>" }
    ])
    data = normalized(activity)[:data]

    assert_equal "direct", data.dig("conversation", "type")
    assert_nil data["thread_id"]
    assert_equal [ { "name" => "brief.pdf", "file_type" => "pdf", "unique_id" => "u1" } ], data["files"]
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
