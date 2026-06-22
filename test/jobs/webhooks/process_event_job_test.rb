# frozen_string_literal: true

require "test_helper"

module Webhooks
  class ProcessEventJobTest < ActiveJob::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.company)
      @workflow = create(:workflow, scope: @user.company)
      @endpoint = create(:webhook_endpoint, provider: :slack, project: @project)
      @binding = create(:trigger_binding,
        project: @project, workflow: @workflow, created_by: @user,
        event_type: "slack.message", filter_predicate: { "channel" => "C1" })
    end

    def received(payload, key: "Ev1")
      ReceivedWebhook.create!(
        webhook_endpoint: @endpoint, idempotency_key: key,
        event_type: "slack", raw_payload: payload
      )
    end

    test "normalizes a Slack message and starts the bound workflow" do
      payload = {
        "type" => "event_callback", "event_id" => "Ev1", "team_id" => "T1",
        "event" => { "type" => "message", "channel" => "C1", "user" => "U1", "text" => "hello" }
      }
      rw = received(payload)

      WorkflowService.expects(:start).with(
        has_entries(workflow: @workflow, user: @user, mode: :non_interactive)
      ).once.returns(build(:workflow_run))

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "processed", rw.reload.status
      assert TriggerEvent.exists?(event_type: "slack.message")
      assert_equal 1, TriggerDispatch.count
    end

    test "ignores the bot's own messages" do
      payload = { "event" => { "type" => "message", "channel" => "C1", "bot_id" => "B1" } }
      rw = received(payload, key: "Ev2")

      WorkflowService.expects(:start).never

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "skipped", rw.reload.status
    end

    test "does not start a workflow when the channel predicate does not match" do
      payload = { "event_id" => "Ev3", "event" => { "type" => "message", "channel" => "OTHER" } }
      rw = received(payload, key: "Ev3")

      WorkflowService.expects(:start).never

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "processed", rw.reload.status
    end
  end
end
