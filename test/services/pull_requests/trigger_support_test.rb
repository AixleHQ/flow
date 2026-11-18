# frozen_string_literal: true

require "test_helper"

# What TriggerEngine does for a pull-request event: one run per pull request at a
# time, and the board task the pull request is about.
class PullRequests::TriggerSupportTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :github, :active, company: @company, project: @project)
    @repository = create(:repository, scope: @project, integration: @integration, full_name: "acme/api")
    @workflow = create(:workflow, scope: @project)
    @column = create(:board_column, board: create(:board, project: @project), name: "Review", position: 1)
  end

  def review(revision)
    PullRequests::Event.build(kind: :review_submitted, number: 12, title: "Add retries", url: "https://github.com/acme/api/pull/12",
                              actor: { id: "7", name: "ada" }, verdict: "changes_requested", body: "Handle the timeout",
                              revision: revision)
  end

  def pr_binding(**attributes)
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                             event_type: "pull_request.review.submitted", **attributes)
  end

  def publish(revision) = PullRequests::EventPipeline.process(review(revision), [ @repository ]).sole

  test "while the trigger's run for a pull request is going, another review of it starts nothing" do
    binding = pr_binding
    first = publish("r-1")
    running = create(:workflow_run, :running, workflow: @workflow, project: @project)
    first.trigger_dispatches.sole.update!(status: "started", workflow_run: running)
    WorkflowService.expects(:enqueue).never

    second = publish("r-2")

    dispatch = second.trigger_dispatches.sole
    assert_equal [ binding.id, "skipped", "pull_request_run_in_progress" ],
                 [ dispatch.trigger_binding_id, dispatch.status, dispatch.detail["reason"] ]
  end

  test "once that run has ended, the next review starts the workflow again" do
    pr_binding
    first = publish("r-1")
    first.trigger_dispatches.sole.update!(status: "started", workflow_run: create(:workflow_run, :completed, workflow: @workflow,
                                                                                                             project: @project))
    WorkflowService.expects(:enqueue).returns(build(:workflow_run))

    publish("r-2")
  end

  test "existing_task lands on the task whose run opened the pull request" do
    task = create(:board_task, board: @column.board, board_column: @column, title: "Retries")
    opener = create(:workflow_run, :completed, workflow: @workflow, project: @project, board_task: task)
    PullRequestOperation.create!(integration: @integration, repository: @repository, operation: "create", operation_key: "k",
                                 request_digest: "d", state: :succeeded, pull_request_number: "12", workflow_run_id: opener.id,
                                 workflow_id: @workflow.id, created_at: 2.days.ago)
    pr_binding(subject_policy: "existing_task")
    WorkflowService.expects(:enqueue).with { |args| args[:task] == task }.returns(build(:workflow_run))

    publish("r-1")
  end

  test "find_or_create_task puts every review of one pull request on one task, linked to it" do
    pr_binding(subject_policy: "find_or_create_task", subject_column: @column)
    tasks = []
    WorkflowService.stubs(:enqueue).with { |args| tasks << args[:task] }.returns(build(:workflow_run))

    publish("r-1")
    publish("r-2")

    assert_equal 1, tasks.uniq.size
    task = tasks.first
    assert_equal "PR 12: Add retries", task.title
    assert_includes task.description, "https://github.com/acme/api/pull/12"
    link = task.external_resources.sole
    assert_equal [ ExternalResource::PULL_REQUEST, "acme/api#12" ], [ link.kind, link.data["key"] ]
  end
end
