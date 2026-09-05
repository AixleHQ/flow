# frozen_string_literal: true

require "test_helper"

module Slack
  class RunFailureNotifierTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @integration = Integration.create!(
        provider: :slack, company: @company, project: @project, connected_by: @user,
        name: "Acme", status: :active
      )
      @integration.update!(credentials_data: { "bot_token" => "xoxb-1" })
      stub_slack_client!

      @workflow = create(:workflow, scope: @project, name: "Weekly Digest")
      # A trigger binding refuses to attach to a workflow with a step that needs
      # a human — an unattended launch would be silently skipped at fire time.
      @step = create(:step, workflow: @workflow, name: "Render Output", position: 1, allow_non_interactive: true)
      @binding = create(:trigger_binding, project: @project, workflow: @workflow, event_type: "slack.message")
    end

    def failed_run(shared_context: slack_context, notify: true, binding: @binding)
      @binding&.update!(notify_on_failure: notify)
      run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user,
        shared_context: shared_context)
      if binding
        event = TriggerEvent.create!(event_type: "slack.message", source: "slack:acme", data: {}, occurred_at: Time.current)
        TriggerDispatch.create!(trigger_event: event, trigger_binding: binding, workflow_run: run,
          dedup_key: "d-#{run.id}", status: "started", source: "trigger_binding")
      end
      create(:step_run, :failed, workflow_run: run, step: @step, error_message: "container exited with code 1")
      run.update_column(:state, "failed")
      run
    end

    def slack_context
      { "slack" => { "channel" => "C1", "thread_ts" => "111.222", "integration_id" => @integration.id } }
    end

    test "replies in the triggering thread with the workflow, the step and its error" do
      assert Slack::RunFailureNotifier.call(failed_run)

      msg = fake_slack.last_posted_message
      assert_equal "xoxb-1", msg[:token]
      assert_equal "C1", msg[:channel]
      assert_equal "111.222", msg[:thread_ts]
      assert_match(/Weekly Digest/, msg[:text])
      assert_match(/Render Output: container exited with code 1/, msg[:text])
      assert_match(%r{/workflow_runs/}, msg[:text])
    end

    test "says the account ran out of credits when that is why the run failed" do
      run = failed_run
      run.update_columns(failure_reason: "quota_exceeded")

      assert Slack::RunFailureNotifier.call(run)
      assert_match(/ran out of credits/, fake_slack.last_posted_message[:text])
    end

    test "stays quiet when the trigger has notifications switched off" do
      assert_not Slack::RunFailureNotifier.call(failed_run(notify: false))
      assert_empty fake_slack.posted_messages
    end

    test "stays quiet for a run that did not come from Slack" do
      assert_not Slack::RunFailureNotifier.call(failed_run(shared_context: {}))
      assert_empty fake_slack.posted_messages
    end

    test "stays quiet for a Slack-context run with no trigger behind it" do
      assert_not Slack::RunFailureNotifier.call(failed_run(binding: nil))
      assert_empty fake_slack.posted_messages
    end

    test "stays quiet for a run that has not failed" do
      run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user,
        shared_context: slack_context)

      assert_not Slack::RunFailureNotifier.call(run)
      assert_empty fake_slack.posted_messages
    end

    test "a Slack outage is swallowed, never raised at the caller" do
      Slack::Notifier.stubs(:post).raises(StandardError, "slack is down")

      assert_not Slack::RunFailureNotifier.call(failed_run)
    end
  end
end
