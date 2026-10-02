# frozen_string_literal: true

require "test_helper"

# What the platform itself says in Teams: help, failure notices, the welcome.
class Teams::RepliesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    with_teams_enabled
    stub_teams_token!
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company, name: "Sales Ops")
    @integration = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso",
                                       status: :active)
    @conversation = ChatConversation.record_teams!(integration: @integration, activity: teams_activity)
    @thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
    @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
    @step = create(:step, workflow: @workflow, name: "Render", position: 1, allow_non_interactive: true)
  end

  def event(text: "help")
    TriggerEvent.create!(event_type: "chat.message", source: "teams:teams-tenant-#{TEAMS_CUSTOMER_TENANT}",
                         company: @company, occurred_at: Time.current, data: {
                           "provider" => "teams", "integration_id" => @integration.id, "channel" => "19:abc@thread.tacv2",
                           "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" },
                           "thread_id" => "1700000000001", "text" => text
                         })
  end

  test "help lists, in the thread, what this conversation can start" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                             filter_predicate: { "text" => { "op" => "starts_with", "value" => "digest" } })
    stub = stub_request(:post, @thread).with { |request|
      body = JSON.parse(request.body)
      body["textFormat"] == "markdown" && body["from"] == { "id" => "28:#{TEAMS_APP_ID}" } &&
        body["text"].include?("**digest** — Weekly Digest (starts\\_with \"digest\") _Sales Ops_")
    }.to_return(status: 201, body: { id: "1" }.to_json)

    assert Chat.answer_help(event)
    assert_requested stub
  end

  test "a failed Teams-started run says so in its thread" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, shared_context: {
      "chat" => { "provider" => "teams", "integration_id" => @integration.id,
                  "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" }, "thread_id" => "1700000000001" }
    })
    create(:step_run, :failed, workflow_run: run, step: @step, error_message: "exit 1")
    run.update_column(:state, "failed")
    stub = stub_request(:post, @thread)
      .with(body: hash_including("text" => "❌ **Weekly Digest** run ##{run.id} failed.\n\n> Render: exit 1\n\n#{Chat::RunFailure.url(run)}"))
      .to_return(status: 201, body: { id: "1" }.to_json)

    assert Teams::RunFailureNotifier.call(run)
    assert_requested stub

    stub_request(:post, @thread).to_return(status: 503)
    assert_raises(Triggers::ReportToOriginJob::Retryable) { Teams::RunFailureNotifier.call(run) }

    stub_request(:post, @thread).to_return(status: 403, body: { error: { code: "BotNotInConversationRoster" } }.to_json)
    assert_not Teams::RunFailureNotifier.call(run)
  end

  test "the welcome goes out once, and not into a large team" do
    stub_request(:get, "#{TEAMS_SERVICE_URL}v3/teams/19%3Ateam%40thread.tacv2")
      .to_return(status: 200, body: { aadGroupId: "1b22f251-0000-4000-8000-000000000001", name: "Sales", memberCount: 12 }.to_json)
    welcome = stub_request(:post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2/activities")
      .with(body: hash_including("text" => /Mention me with a request/))
      .to_return(status: 201, body: { id: "1" }.to_json)

    2.times { Teams::WelcomeJob.perform_now(@conversation.id) }

    assert_requested welcome, times: 1
    assert_equal "1b22f251-0000-4000-8000-000000000001", @conversation.reload.team_aad_group_id

    big = ChatConversation.record_teams!(integration: @integration, activity: teams_activity.deep_merge(
      "conversation" => { "id" => "19:big@thread.tacv2" }, "channelData" => { "team" => { "id" => "19:big-team@thread.tacv2" } }
    ))
    stub_request(:get, "#{TEAMS_SERVICE_URL}v3/teams/19%3Abig-team%40thread.tacv2")
      .to_return(status: 200, body: { aadGroupId: "x", memberCount: 208 }.to_json)

    Teams::WelcomeJob.perform_now(big.id)

    assert_not_nil big.reload.welcomed_at
    assert_not_requested :post, "#{TEAMS_SERVICE_URL}v3/conversations/19%3Abig%40thread.tacv2/activities"
  end
end
