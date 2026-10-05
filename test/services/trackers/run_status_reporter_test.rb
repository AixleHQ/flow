# frozen_string_literal: true

require "test_helper"

class Trackers::RunStatusReporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @tracker = create(:project_tracker, :primary, integration: @integration)
    @fakes = stub_azure_devops!(integration: @integration)
    @workflow = create(:workflow, scope: @project, name: "Intake")
    @binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                        event_type: "tracker.issue.created")
    @event = create(:trigger_event, event_type: "tracker.issue.created", source: "tracker", project: @project,
                                    data: { "tracker" => { "id" => @tracker.id }, "issue" => { "id" => "11" } })
    @run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    @dispatch = TriggerDispatch.create!(trigger_event: @event, trigger_binding: @binding, workflow_run: @run,
                                        dedup_key: SecureRandom.hex, status: "started")
  end

  test "a failed tracker-started run says so once on the issue, attributed to the run" do
    @run.update!(state: "failed", failure_reason: "step_failed")

    Trackers::RunStatusReporter.report(@dispatch, "failed")
    Trackers::RunStatusReporter.report(@dispatch, "failed")

    comments = @fakes.work_items.calls_to(:add_comment)
    assert_equal 1, comments.size
    assert_match(/Intake run for this issue failed/, comments.sole[:text])
    assert_match(%r{/workflow_runs/#{@run.id}}, comments.sole[:text])
    assert_equal [ @run.id, "11" ], TrackerOperation.sole.then { |op| [ op.workflow_run_id, op.issue_id ] }
  end

  test "a late job for a transition the run is no longer in does nothing" do
    Trackers::RunStatusReporter.report(@dispatch, "failed")

    assert_empty @fakes.work_items.calls_to(:add_comment)
  end

  test "it applies to tracker bindings that report failures, never to other sources" do
    assert Trackers::RunStatusReporter.applies?(@dispatch)

    @binding.update!(notify_on_failure: false)
    refute Trackers::RunStatusReporter.applies?(@dispatch.reload)

    slack = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user)
    refute Trackers::RunStatusReporter.applies?(TriggerDispatch.new(trigger_event: @event, trigger_binding: slack))
  end

  test "a provider hiccup is retried; a refusal is not" do
    @run.update!(state: "failed")
    @fakes.work_items.instance_variable_set(:@error, AzureDevops::RateLimited.new("slow"))
    assert_raises(Triggers::ReportToOriginJob::Retryable) { Trackers::RunStatusReporter.report(@dispatch, "failed") }

    @fakes.work_items.instance_variable_set(:@error, AzureDevops::NotFound.new("gone"))
    Trackers::RunStatusReporter.report(@dispatch, "failed")
    assert_equal "failed", TrackerOperation.sole.state
  end

  test "a comment resent after a refusal is attributed to the run, even when its event overtakes it" do
    @run.update!(state: "failed")
    @fakes.work_items.instance_variable_set(:@error, AzureDevops::RateLimited.new("slow"))
    assert_raises(Triggers::ReportToOriginJob::Retryable) { Trackers::RunStatusReporter.report(@dispatch, "failed") }
    @fakes.work_items.instance_variable_set(:@error, nil)

    events = nil
    @fakes.work_items.before_answering(:add_comment) do
      comment = Trackers::Notification.build(kind: :comment_created, scope_id: @tracker.external_scope_id, issue_id: "11",
                                             revision: 9, comment_text: "Aixle: the Intake run failed", actor: { name: "Ada" })
      events = Trackers::EventPipeline.new(@integration).process(comment)
    end
    Trackers::RunStatusReporter.report(@dispatch, "failed")

    assert_equal [ true, @run.id ], events.sole.data["origin"].values_at("attributed", "workflow_run_id")
    assert_equal "succeeded", TrackerOperation.sole.state
  end

  test "failing or cancelling a run announces the transition for every dispatch that started it" do
    assert_enqueued_with(job: Triggers::ReportRunTransitionJob, args: [ @dispatch.id, "failed" ]) { @run.fail! }

    cancelled = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    other = TriggerDispatch.create!(trigger_event: @event, trigger_binding: @binding, workflow_run: cancelled,
                                    dedup_key: SecureRandom.hex, status: "started")
    assert_enqueued_with(job: Triggers::ReportRunTransitionJob, args: [ other.id, "cancelled" ]) { cancelled.cancel! }
  end

  test "the fan-out gives each applicable reporter its own job" do
    assert_enqueued_with(job: Triggers::ReportToOriginJob, args: [ @dispatch.id, "failed", "Trackers::RunStatusReporter" ]) do
      Triggers::ReportRunTransitionJob.perform_now(@dispatch.id, "failed")
    end
  end

  test "a run starting or completing gives the tracker reporter nothing to do" do
    assert_no_enqueued_jobs(only: Triggers::ReportToOriginJob) do
      Triggers::ReportRunTransitionJob.perform_now(@dispatch.id, "running")
      Triggers::ReportRunTransitionJob.perform_now(@dispatch.id, "completed")
    end
  end
end
