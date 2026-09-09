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

    test "says the run timed out when it was reaped as stale" do
      run = failed_run
      run.update_columns(failure_reason: "stale_run")

      assert Slack::RunFailureNotifier.call(run)
      assert_match(/timed out and was cleaned up as stale/, fake_slack.last_posted_message[:text])
    end

    test "scrubs credentials out of the failure reason" do
      run = failed_run
      run.step_runs.last.update!(error_message: "auth failed with token=xoxb-999-secret-abc")

      assert Slack::RunFailureNotifier.call(run)
      text = fake_slack.last_posted_message[:text]
      assert_no_match(/xoxb-999-secret-abc/, text)
      assert_match(/\[redacted\]/, text)
    end

    test "a second call does not post the failure twice in the thread" do
      run = failed_run

      assert Slack::RunFailureNotifier.call(run)
      assert_not Slack::RunFailureNotifier.call(run)
      assert_equal 1, fake_slack.posted_messages.size
    end

    test "a Slack outage releases the claim so a later call can still post" do
      run = failed_run
      dispatch = TriggerDispatch.where(workflow_run_id: run.id).order(:id).last

      Slack::Notifier.stubs(:post).returns(false).then.returns(true)

      assert_not Slack::RunFailureNotifier.call(run)
      assert_nil dispatch.reload.slack_failure_notified_at

      assert Slack::RunFailureNotifier.call(run)
      assert_not_nil dispatch.reload.slack_failure_notified_at
    end

    # == launch-skip entry point ==

    def skipped_dispatch(reason: "step 'Approve' needs a human", notify: true)
      @binding.update!(notify_on_failure: notify)
      event = TriggerEvent.create!(
        event_type: "slack.message", source: "slack:acme", occurred_at: Time.current,
        data: { "channel" => "C1", "ts" => "111.222", "integration_id" => @integration.id }
      )
      TriggerDispatch.create!(
        trigger_event: event, trigger_binding: @binding, dedup_key: "d-skip-#{event.id}",
        status: "skipped", source: "trigger_binding", detail: { "reason" => reason }
      )
    end

    test "notify_launch_skip replies in the thread with the workflow and the skip reason" do
      assert Slack::RunFailureNotifier.notify_launch_skip(skipped_dispatch)

      msg = fake_slack.last_posted_message
      assert_equal "C1", msg[:channel]
      assert_equal "111.222", msg[:thread_ts]
      assert_match(/Weekly Digest/, msg[:text])
      assert_match(/needs a human/, msg[:text])
    end

    test "notify_launch_skip is idempotent" do
      dispatch = skipped_dispatch

      assert Slack::RunFailureNotifier.notify_launch_skip(dispatch)
      assert_not Slack::RunFailureNotifier.notify_launch_skip(dispatch)
      assert_equal 1, fake_slack.posted_messages.size
    end

    test "notify_launch_skip stays quiet when the trigger has notifications off" do
      assert_not Slack::RunFailureNotifier.notify_launch_skip(skipped_dispatch(notify: false))
      assert_empty fake_slack.posted_messages
    end

    test "notify_launch_skip stays quiet for a dispatch that actually started" do
      dispatch = skipped_dispatch
      dispatch.update!(status: "started")

      assert_not Slack::RunFailureNotifier.notify_launch_skip(dispatch)
      assert_empty fake_slack.posted_messages
    end
  end
end
