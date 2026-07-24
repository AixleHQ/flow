# frozen_string_literal: true

require "test_helper"

module Webhooks
  class ProcessEventJobTest < ActiveJob::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.company)
      @workflow = create(:workflow, scope: @project)
      # Slack endpoints are company-scoped (one workspace serves every project).
      @endpoint = create(:webhook_endpoint, provider: :slack, project: nil, company: @user.company)
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

    test "starts the bound workflow on an app_mention" do
      payload = {
        "type" => "event_callback", "event_id" => "Ev1", "team_id" => "T1",
        "event" => { "type" => "app_mention", "channel" => "C1", "user" => "U1", "text" => "<@B> hello" }
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

    test "a company-scoped Slack event fans out to bindings across the company's projects" do
      project_b = create(:project, owner: @user, company: @user.company)
      workflow_b = create(:workflow, scope: project_b)
      create(:trigger_binding, project: project_b, workflow: workflow_b, created_by: @user,
        event_type: "slack.message", filter_predicate: { "channel" => "C1" })

      payload = {
        "type" => "event_callback", "event_id" => "EvFan", "team_id" => "T1",
        "event" => { "type" => "app_mention", "channel" => "C1", "user" => "U1", "text" => "<@B> hi" }
      }
      rw = received(payload, key: "EvFan")

      # Both projects' triggers fire from the one workspace event.
      WorkflowService.expects(:start).twice.returns(build(:workflow_run))

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal 2, TriggerDispatch.count
    end

    test "ignores plain channel messages that do not mention the bot" do
      payload = {
        "type" => "event_callback", "event_id" => "EvMsg", "team_id" => "T1",
        "event" => { "type" => "message", "channel" => "C1", "user" => "U1", "text" => "just chatting" }
      }
      rw = received(payload, key: "EvMsg")

      WorkflowService.expects(:start).never

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "skipped", rw.reload.status
      assert_not TriggerEvent.exists?(event_type: "slack.message")
    end

    test "ignores the bot's own messages" do
      payload = { "event" => { "type" => "app_mention", "channel" => "C1", "bot_id" => "B1" } }
      rw = received(payload, key: "Ev2")

      WorkflowService.expects(:start).never

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "skipped", rw.reload.status
    end

    test "threads Slack reply context and the message into shared_context; whitelists attachments" do
      integration = Integration.create!(
        provider: :slack, company: @user.company, project: @project, connected_by: @user,
        name: "Acme", status: :active, settings: { "team_id" => "T1" }
      )
      @endpoint.update!(config: { "integration_id" => integration.id })

      payload = {
        "type" => "event_callback", "event_id" => "EvF", "team_id" => "T1",
        "event" => {
          "type" => "app_mention", "channel" => "C1", "user" => "U1", "text" => "run report",
          "ts" => "111.222",
          "files" => [ { "id" => "F1", "name" => "spec.pdf", "url_private" => "https://files/x",
                         "mimetype" => "application/pdf", "size" => 10, "extra" => "drop" } ]
        }
      }
      rw = received(payload, key: "EvF")

      WorkflowService.expects(:start).with(
        has_entries(
          workflow: @workflow,
          shared_context: has_entries(
            "slack" => has_entries("channel" => "C1", "thread_ts" => "111.222",
                                   "team" => "T1", "integration_id" => integration.id,
                                   "text" => "run report", "user" => "U1")
          )
        )
      ).once.returns(build(:workflow_run))

      Webhooks::ProcessEventJob.perform_now(rw.id)

      event = TriggerEvent.find_by(event_type: "slack.message")
      assert_equal "111.222", event.data["ts"]
      assert_equal "F1", event.data.dig("files", 0, "id")
      assert_nil event.data.dig("files", 0, "extra") # only whitelisted file fields kept
      assert_equal integration.id, event.data["integration_id"]
    end

    test "ingests Slack attachments into the matching binding's project at fire time" do
      integration = Integration.create!(
        provider: :slack, company: @user.company, project: nil, connected_by: @user,
        name: "Acme", status: :active
      )
      integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
      @endpoint.update!(config: { "integration_id" => integration.id })

      fake_slack = stub_slack_client!
      fake_slack.file_body = "BYTES"
      captured = nil
      WorkflowService.expects(:start).with { |kw| captured = kw; true }.returns(build(:workflow_run))

      payload = {
        "type" => "event_callback", "event_id" => "EvFiles", "team_id" => "T1",
        "event" => {
          "type" => "app_mention", "channel" => "C1", "ts" => "1.1",
          "files" => [ { "id" => "F1", "name" => "in.txt", "url_private" => "https://files.slack.com/in.txt", "size" => 5 } ]
        }
      }
      rw = received(payload, key: "EvFiles")

      assert_difference -> { Asset.count }, 1 do
        Webhooks::ProcessEventJob.perform_now(rw.id)
      end

      # The Slack file was downloaded once from its private URL to build the asset.
      assert_equal 1, fake_slack.downloads.length
      assert_equal "https://files.slack.com/in.txt", fake_slack.last_download[:url]

      # Ingested at fire time for the firing binding's project and forwarded to the run.
      assert_equal @project, captured[:project]
      assert_equal [ Asset.last.id ], captured[:input_asset_ids]
    end

    test "does not start a workflow when the channel predicate does not match" do
      payload = { "event_id" => "Ev3", "event" => { "type" => "app_mention", "channel" => "OTHER" } }
      rw = received(payload, key: "Ev3")

      WorkflowService.expects(:start).never

      Webhooks::ProcessEventJob.perform_now(rw.id)

      assert_equal "processed", rw.reload.status
    end
  end
end
