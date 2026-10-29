# frozen_string_literal: true

require "test_helper"

# Which runner a run takes, and what happens at launch when it names one
# (DESIGN.md §3.3, §3.4, §12.2).
class WorkflowServiceRunnerTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project, name: "Deploy")
    @build = create(:step, workflow: @workflow, position: 1, name: "Build")
    @ship = create(:step, workflow: @workflow, position: 2, name: "Ship")
    create(:agent_credential, user: @user, company: @company)
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
    @other = create(:runner, company: @company, created_by: @user, name: "GPU box")
  end

  # == precedence and freezing ==

  test "a run takes its workflow's runner, or runs hosted without one" do
    hosted = enqueue
    @workflow.update!(runner: @runner)

    assert_nil hosted.runner_id
    assert_equal @runner.id, enqueue.runner_id
  end

  test "a pick at launch beats the workflow's runner, hosted included" do
    @workflow.update!(runner: @runner)

    picked, hosted = with_feature(:external_runners, true, company: @company) do
      [ enqueue(runner_id: @other.id), enqueue(runner_id: nil) ]
    end

    assert_equal @other.id, picked.runner_id
    assert_nil hosted.runner_id
    assert hosted.persisted?
  end

  test "the runner is frozen at creation: changing the workflow's moves no run, and a retry keeps it" do
    @workflow.update!(runner: @runner)
    run = enqueue
    @workflow.update!(runner: @other)

    assert_equal @runner.id, run.reload.runner_id

    run.update_columns(state: "failed")
    TemporalService.stubs(:workflow_open?).returns(false)
    retried = WorkflowService.retry_step(step_run: run.step_runs.first)
    assert_equal @runner.id, retried[:run].runner_id
  end

  test "an automated launch carries no pick, so it takes the workflow's runner" do
    @workflow.update!(runner: @runner)
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    event = TriggerEngine.record_event(event_type: "test.event", source: "test", subject: task.id, data: {},
                                       project: @project, board_task: task, actor: @user)

    run = TriggerEngine.fire_workflow(workflow: @workflow, project: @project, actor: @user, event: event,
                                      source: "column_workflow_binding", task: task)

    assert_equal @runner.id, run.runner_id
  end

  test "without the flag a pick is refused, hosted included, and no run is created" do
    @workflow.update!(runner: @runner)

    runs = with_feature(:external_runners, false, company: @company) do
      [ enqueue(runner_id: @other.id), enqueue(runner_id: nil) ]
    end

    runs.each do |run|
      assert_not run.persisted?
      assert_equal [ "External runners are not enabled for this company." ], run.errors.full_messages
    end
  end

  test "a pick of a runner the project cannot see is refused" do
    run = with_feature(:external_runners, true, company: @company) { enqueue(runner_id: create(:runner).id) }

    assert_not run.persisted?
    assert_match(/is not available to project/, run.errors.full_messages.to_sentence)
  end

  # == launch ==

  test "a run on a runner fails before it is dispatched, and every step and the board task say why" do
    @workflow.update!(runner: @runner)
    task = create_task
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    run = with_feature(:external_runners, true, company: @company) do
      WorkflowService.start(workflow: @workflow, project: @project, user: @user, source: :web, task: task)
    end

    message = "Runner \"Prod VPC\" can't take sessions yet: runner execution not enabled."
    assert_equal "failed", run.reload.state
    assert_nil run.started_at
    assert_equal "runner_execution_not_enabled", run.failure_reason
    assert_equal [ message ] * 2, run.step_runs.map(&:error_message)
    assert_equal %w[failed failed], run.step_runs.map(&:state)
    assert_equal 0, TerminalSession.count

    comment = task.task_comments.sole
    assert_equal "system", comment.author_type
    assert_equal "Run ##{run.id} of workflow \"Deploy\" failed: #{message}", comment.body
    assert task.board_activities.exists?(event_type: "workflow_failed")
  end

  test "a run whose workflow names a disabled runner fails with that, and never falls back to hosted" do
    @workflow.update!(runner: @runner)
    @runner.disable!
    TemporalWorkflowRegistry.expects(:start_workflow_execution).never

    run = with_feature(:external_runners, true, company: @company) { start }

    assert_equal "failed", run.reload.state
    assert_equal "runner_unavailable", run.failure_reason
    assert_equal "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner on the workflow.",
                 run.step_runs.first.error_message
  end

  test "with the flag off for the company the workflow's runner fails the run" do
    @workflow.update!(runner: @runner)

    run = with_feature(:external_runners, false, company: @company) { start }

    assert_equal "failed", run.reload.state
    assert_equal "runner_unavailable", run.failure_reason
    assert_equal "External runners are not enabled for this company.", run.step_runs.first.error_message
  end

  test "the relay fails a run it re-drives the same way" do
    @workflow.update!(runner: @runner)
    run = enqueue

    with_feature(:external_runners, true, company: @company) { WorkflowService.dispatch!(run) }

    assert_equal "failed", run.reload.state
    assert_not_includes WorkflowRun.stuck_for_relay(1.hour.from_now), run
  end

  test "a hosted run is dispatched as before" do
    TemporalWorkflowRegistry.expects(:start_workflow_execution).once.returns(ok: true)

    run = with_feature(:external_runners, true, company: @company) { start }

    assert_equal "pending", run.reload.state
    assert_nil run.failure_reason
    assert_equal "dispatched", run.relay_state
  end

  test "a step refused when its session is about to be built fails, and the board task says why" do
    @workflow.update!(runner: @runner)
    task = create_task
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task,
                                          runner: @runner)
    step_run = create(:step_run, workflow_run: run, step: @build)
    refusal = Runners::Resolver::Refused.new("runner_unavailable", "Runner \"Prod VPC\" is disabled.")

    WorkflowService.fail_step_on_runner_refusal(step_run: step_run, refusal: refusal)

    assert_equal [ "failed", "Runner \"Prod VPC\" is disabled." ], [ step_run.reload.state, step_run.error_message ]
    assert_equal "runner_unavailable", run.reload.failure_reason
    assert_match(/Runner "Prod VPC" is disabled\./, task.task_comments.sole.body)
  end

  private

  def enqueue(**args)
    WorkflowService.enqueue(workflow: @workflow, project: @project, user: @user, source: :web, **args)
  end

  def start(**args)
    WorkflowService.start(workflow: @workflow, project: @project, user: @user, source: :web, **args)
  end

  def create_task
    board = create(:board, project: @project)
    create(:board_task, board: board, board_column: create(:board_column, board: board))
  end
end
