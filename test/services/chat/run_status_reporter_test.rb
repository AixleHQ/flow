# frozen_string_literal: true

require "test_helper"

class Chat::RunStatusReporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
    @integration = Integration.create!(provider: :slack, company: @project.company, project: nil,
                                       connected_by: @user, name: "Acme", status: :active)
    @integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
    stub_slack_client!

    @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
    @step = create(:step, workflow: @workflow, name: "Render", position: 1, allow_non_interactive: true)
    @binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                        event_type: "slack.message")
    @event = create(:trigger_event, event_type: "chat.message", source: "slack:slack-team-T1",
                                    data: { "provider" => "slack" }, company: @project.company)
    @run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, shared_context: {
      "slack" => { "channel" => "C1", "thread_ts" => "1.1", "integration_id" => @integration.id }
    })
    @dispatch = TriggerDispatch.create!(trigger_event: @event, trigger_binding: @binding, workflow_run: @run,
                                        dedup_key: SecureRandom.hex, status: "started")
  end

  test "a failed chat-started run says so in the thread it came from" do
    create(:step_run, :failed, workflow_run: @run, step: @step, error_message: "exit 1")
    @run.update_column(:state, "failed")

    Chat::RunStatusReporter.report(@dispatch, "failed")

    message = fake_slack.last_posted_message
    assert_equal [ "C1", "1.1" ], message.values_at(:channel, :thread_ts)
    assert_match(/Weekly Digest.*failed/, message[:text])
  end

  test "a late job for a transition the run is no longer in says nothing" do
    Chat::RunStatusReporter.report(@dispatch, "failed")
    @run.update_column(:state, "failed")
    Chat::RunStatusReporter.report(@dispatch, "cancelled")

    assert_empty fake_slack.posted_messages
  end

  test "it applies to chat triggers that report, never to silent ones or other sources" do
    assert Chat::RunStatusReporter.applies?(@dispatch)

    @binding.update!(status_reporting: "none")
    assert_not Chat::RunStatusReporter.applies?(@dispatch.reload)

    tracker = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                       event_type: "webhook.received")
    assert_not Chat::RunStatusReporter.applies?(TriggerDispatch.new(trigger_event: @event, trigger_binding: tracker))

    forged = create(:trigger_event, event_type: "chat.message", source: "generic:wh-1", data: { "provider" => "slack" })
    assert_not Chat::RunStatusReporter.applies?(TriggerDispatch.new(trigger_event: forged, trigger_binding: @binding))
  end

  test "failing a chat-started run reaches the thread through the run-transition seam" do
    create(:step_run, :failed, workflow_run: @run, step: @step, error_message: "exit 1")

    @run.fail!
    2.times { perform_enqueued_jobs }

    assert_match(/Weekly Digest.*failed/, fake_slack.last_posted_message[:text])
  end
end
