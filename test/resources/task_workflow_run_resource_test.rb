# frozen_string_literal: true

require "test_helper"

class TaskWorkflowRunResourceTest < ActiveSupport::TestCase
  setup do
    @workflow = create(:workflow, :with_project_scope)
    @project = @workflow.scope
    @run = create(:workflow_run, workflow: @workflow, project: @project)
    @user = @run.user
  end

  test "steps expose the terminal session id so the board task drawer can link into the session" do
    session = create(:terminal_session, project: @project, user: @user)
    step = create(:step, workflow: @workflow, name: "Implementation")
    create(:step_run, workflow_run: @run, step: step, terminal_session: session)

    steps = TaskWorkflowRunResource.new(@run.reload).to_h["steps"]

    assert_equal 1, steps.length
    assert_equal "Implementation", steps.first["name"]
    assert_equal session.id, steps.first["terminalSessionId"]
  end

  test "steps report a nil terminal session id when no session was started" do
    step = create(:step, workflow: @workflow, name: "Analysis")
    create(:step_run, workflow_run: @run, step: step)

    steps = TaskWorkflowRunResource.new(@run.reload).to_h["steps"]

    assert_nil steps.first["terminalSessionId"]
  end

  test "steps serialize a preloaded run without querying step_runs again" do
    step = create(:step, workflow: @workflow, name: "Implementation")
    create(:step_run, workflow_run: @run, step: step)

    preloaded = WorkflowRun.where(id: @run.id).includes(:workflow, step_runs: %i[step terminal_session]).first

    assert_no_queries do
      assert_equal [ "Implementation" ], TaskWorkflowRunResource.new(preloaded).to_h["steps"].map { |s| s["name"] }
    end
  end

  test "a run and its steps are timed from leaving the queue, not from being dispatched" do
    freeze_time do
      @run.update_columns(state: "completed", started_at: 30.minutes.ago, execution_started_at: 20.minutes.ago,
                          completed_at: Time.current)
      session = create(:terminal_session, project: @project, user: @user, state: "finished",
                                          started_at: 20.minutes.ago, finished_at: 5.minutes.ago)
      create(:step_run, :completed, workflow_run: @run, step: create(:step, workflow: @workflow),
                                    started_at: 30.minutes.ago, completed_at: 5.minutes.ago, terminal_session: session)
      create(:step_run, :failed, workflow_run: @run, step: create(:step, workflow: @workflow),
                                 started_at: 5.minutes.ago, completed_at: Time.current)

      resource = TaskWorkflowRunResource.new(@run.reload).to_h

      assert_equal 20.minutes.to_i, resource["durationSeconds"]
      assert_equal [ 15.minutes.to_i, nil ], resource["steps"].map { |s| s["durationSeconds"] }
    end
  end

  test "steps keep creation order so the drawer can pick the most recent session" do
    first = create(:step_run, workflow_run: @run, step: create(:step, workflow: @workflow, name: "Analysis"),
                              terminal_session: create(:terminal_session, project: @project, user: @user))
    second = create(:step_run, workflow_run: @run, step: create(:step, workflow: @workflow, name: "Implementation"),
                               terminal_session: create(:terminal_session, project: @project, user: @user))

    steps = TaskWorkflowRunResource.new(@run.reload).to_h["steps"]

    assert_equal [ first.terminal_session_id, second.terminal_session_id ],
                 steps.map { |s| s["terminalSessionId"] }
  end
end
