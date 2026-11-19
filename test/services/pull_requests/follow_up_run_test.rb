# frozen_string_literal: true

require "test_helper"

# The reviews and comments a pull-request run held back while it worked are
# taken up when it ends: one more run, for the latest of them.
class PullRequests::FollowUpRunTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
    integration = create(:integration, :github, :active, company: company, project: @project)
    @repository = create(:repository, scope: @project, integration: integration, full_name: "acme/api")
    @workflow = create(:workflow, scope: @project)
    @binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                                        event_type: "pull_request.comment.created")
  end

  def comment(id)
    event = PullRequests::Event.build(kind: :comment_created, number: 12, title: "Add retries", actor: { id: "7", name: "ada" },
                                      body: "Comment #{id}", comment_id: id)
    PullRequests::EventPipeline.process(event, [ @repository ]).sole
  end

  # The first comment's run, still going, and two comments held back meanwhile.
  def run_with_two_held_back
    first = comment("c-1")
    run = create(:workflow_run, :running, workflow: @workflow, project: @project)
    first.trigger_dispatches.sole.update!(status: "started", workflow_run: run)
    held = [ comment("c-2"), comment("c-3") ].map { |event| event.trigger_dispatches.sole }
    [ run, first.trigger_dispatches.sole, held ]
  end

  def finish(run, dispatch, state)
    run.update_columns(state: state)
    PullRequests::FollowUpRun.report(dispatch, state)
  end

  test "a finished run starts one more, for the latest comment held back, and says how many it covers" do
    run, dispatch, (second, third) = run_with_two_held_back
    follow_up = create(:workflow_run, workflow: @workflow, project: @project)
    WorkflowService.expects(:enqueue).once.with { |args| args[:shared_context].dig("pull_request", "comment", "id") == "c-3" }
                   .returns(follow_up)
    WorkflowService.stubs(:dispatch_or_leave_to_relay)

    finish(run, dispatch, "completed")

    assert_equal [ "started", follow_up.id, { "follows_run" => run.id, "events" => 2 } ],
                 third.reload.values_at(:status, :workflow_run_id, :detail)
    assert_equal [ "skipped", PullRequests::TriggerSupport::COALESCED, third.id ],
                 [ second.reload.status, second.detail["reason"], second.detail["into"] ]
  end

  # A review and its line comments land within a second, before the agent has
  # read anything; it reads them with the rest of the pull request.
  test "what arrived before the run's session started needs no follow-up" do
    run, dispatch, = run_with_two_held_back
    run.update_columns(execution_started_at: 1.second.from_now)
    WorkflowService.expects(:enqueue).never

    finish(run, dispatch, "completed")
  end

  test "a cancelled run starts nothing: someone stopped the work" do
    run, dispatch, = run_with_two_held_back
    WorkflowService.expects(:enqueue).never

    assert_not PullRequests::FollowUpRun.applies?(dispatch, "cancelled")
    finish(run, dispatch, "cancelled")
  end

  test "a run with nothing held back starts nothing" do
    first = comment("c-1")
    run = create(:workflow_run, :running, workflow: @workflow, project: @project)
    first.trigger_dispatches.sole.update!(status: "started", workflow_run: run)
    WorkflowService.expects(:enqueue).never

    finish(run, first.trigger_dispatches.sole, "completed")
  end

  test "while another run of the workflow works on the pull request, the held-back comments wait for it" do
    run, dispatch, = run_with_two_held_back
    other = create(:workflow_run, :running, workflow: @workflow, project: @project)
    comment("c-4").trigger_dispatches.sole.update!(status: "started", workflow_run: other)
    WorkflowService.expects(:enqueue).never

    finish(run, dispatch, "completed")
  end
end
