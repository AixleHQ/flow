# frozen_string_literal: true

require "test_helper"

# The status card a lifecycle chat trigger keeps in the thread its request came
# from, through the run-transition seam, against Teams' Connector (WebMock) and
# Slack (its fake client).
class Chat::StatusCardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    with_teams_enabled
    stub_teams_token!
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
    @step = create(:step, workflow: @workflow, name: "Render", position: 1, allow_non_interactive: true)
    @teams = Integration.create!(provider: :teams, company: @company, connected_by: @user, name: "Contoso", status: :active)
    ChatConversation.record_teams!(integration: @teams, activity: teams_activity)
    @thread = "#{TEAMS_SERVICE_URL}v3/conversations/19%3Aabc%40thread.tacv2%3Bmessageid%3D1700000000001/activities"
  end

  def teams_dispatch(run: nil, status: "started", detail: {})
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "chat.message",
                                       filter_predicate: { "provider" => "teams" }, status_reporting: "lifecycle")
    event = create(:trigger_event, event_type: "chat.message", source: "teams:teams-tenant-#{TEAMS_CUSTOMER_TENANT}",
                                   company: @company, data: {
                                     "provider" => "teams", "integration_id" => @teams.id,
                                     "conversation" => { "id" => "19:abc@thread.tacv2", "type" => "channel" },
                                     "thread_id" => "1700000000001"
                                   })
    TriggerDispatch.create!(trigger_event: event, trigger_binding: binding, workflow_run: run, status: status,
                            detail: detail, dedup_key: SecureRandom.hex)
  end

  def card_text(request)
    JSON.parse(request.body).dig("attachments", 0, "content", "body", 0, "text")
  end

  test "a Teams card is posted once into the thread and then edited as the run moves" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    dispatch = teams_dispatch(run: run)
    posted = stub_request(:post, @thread).with { |request| card_text(request) == "⏳ Accepted — Weekly Digest · run ##{run.id}" }
                                         .to_return(status: 201, body: { id: "1700000000555" }.to_json)
    Chat::RunStatusReporter.report(dispatch, "dispatched")
    assert_requested posted
    assert_equal({ "message_id" => "1700000000555", "state" => "accepted" }, dispatch.reload.detail["chat_status"])

    run.update_columns(state: "running", started_at: Time.utc(2026, 10, 6, 12, 4))
    edited = stub_request(:put, "#{@thread}/1700000000555").with { |request|
      body = JSON.parse(request.body)
      body["id"] == "1700000000555" && card_text(request) == "▶️ Running — Weekly Digest · run ##{run.id}" &&
        body.dig("attachments", 0, "content", "body", 1, "text") == "Since {{TIME(2026-10-06T12:04:00Z)}}"
    }.to_return(status: 200, body: "{}")
    Chat::RunStatusReporter.report(dispatch, "running")
    Chat::RunStatusReporter.report(dispatch, "running")
    assert_requested edited, times: 1

    create(:step_run, :failed, workflow_run: run, step: @step, error_message: "exit 1")
    run.update_columns(state: "failed")
    failed = stub_request(:put, "#{@thread}/1700000000555").with { |request|
      body = JSON.parse(request.body)
      card_text(request) == "❌ Failed — Weekly Digest · run ##{run.id}" &&
        body.dig("attachments", 0, "content", "body", 1, "text") == "Render: exit 1" &&
        body.dig("attachments", 0, "content", "actions", 0, "url") == Chat::RunFailure.url(run)
    }.to_return(status: 200, body: "{}")
    # A late `running` job renders what the run is now, not what woke it.
    Chat::RunStatusReporter.report(dispatch, "running")
    assert_requested failed, times: 1
  end

  test "a request no run came of says why" do
    dispatch = teams_dispatch(status: "skipped", detail: { "reason" => "cooldown" })
    posted = stub_request(:post, @thread).with { |request|
      body = JSON.parse(request.body)
      card_text(request) == "⏭️ Not started — Weekly Digest" &&
        body.dig("attachments", 0, "content", "body", 1, "text").include?("cooling down")
    }.to_return(status: 201, body: { id: "9" }.to_json)

    Chat::RunStatusReporter.report(dispatch, "skipped")

    assert_requested posted
  end

  test "a Teams throttle is retried later, and a conversation the bot left is dropped" do
    dispatch = teams_dispatch(run: create(:workflow_run, workflow: @workflow, project: @project, user: @user))
    stub_request(:post, @thread).to_return(status: 429, headers: { "Retry-After" => "0" })
    assert_raises(Triggers::ReportToOriginJob::Retryable) { Chat::RunStatusReporter.report(dispatch, "dispatched") }

    ChatConversation.update_all(installed: false)
    Chat::RunStatusReporter.report(dispatch, "dispatched")
    assert_nil dispatch.reload.detail.dig("chat_status", "message_id")
  end

  test "a Slack card is Block Kit in the thread, edited with chat.update" do
    stub_slack_client!
    slack = Integration.create!(provider: :slack, company: @company, connected_by: @user, name: "Acme", status: :active)
    slack.update!(credentials_data: { "bot_token" => "xoxb-1" })
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                       event_type: "chat.message", status_reporting: "lifecycle")
    event = create(:trigger_event, event_type: "chat.message", source: "slack:slack-team-T1", company: @company, data: {
      "provider" => "slack", "integration_id" => slack.id, "channel" => "C1", "ts" => "1.2", "thread_ts" => "1.1"
    })
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    dispatch = TriggerDispatch.create!(trigger_event: event, trigger_binding: binding, workflow_run: run,
                                       status: "started", dedup_key: SecureRandom.hex)

    Chat::RunStatusReporter.report(dispatch, "dispatched")
    posted = fake_slack.last_posted_message
    assert_equal [ "C1", "1.1", "Accepted: Weekly Digest" ], posted.values_at(:channel, :thread_ts, :text)
    assert_match(/Accepted\* — Weekly Digest · run ##{run.id}/, posted[:blocks].first.dig(:text, :text))

    run.update_columns(state: "completed", started_at: 5.minutes.ago, completed_at: Time.current)
    Chat::RunStatusReporter.report(dispatch, "completed")
    updated = fake_slack.last_updated_message
    assert_equal posted[:ts], updated[:ts]
    assert_match(/Completed\*.*\nTook 5 minutes/, updated[:blocks].first.dig(:text, :text))
  end

  test "lifecycle triggers hear every transition; failure-only ones just the failure" do
    dispatch = teams_dispatch
    assert Chat::RunStatusReporter.applies?(dispatch, "running")

    dispatch.trigger_binding.update!(status_reporting: "failures")
    assert_not Chat::RunStatusReporter.applies?(dispatch.reload, "running")
    assert Chat::RunStatusReporter.applies?(dispatch, "failed")
  end
end
