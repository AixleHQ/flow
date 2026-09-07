# frozen_string_literal: true

require "test_helper"

# The card reads `state` off the runs in this payload, so what this resource
# says about a run is what the board tells a human at a glance.
class BoardTaskResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
    @workflow = create(:workflow, scope: @project)
  end

  def run_with_session(state, run_state: :running)
    run = create(:workflow_run, run_state, workflow: @workflow, project: @project, user: @user, board_task: @task)
    step_run = create(:step_run, workflow_run: run)
    step_run.update!(terminal_session: create(:terminal_session, project: @project, user: @user,
                                              session_type: "workflow_step", state: state))
    run
  end

  test "a run waiting for a session slot is reported as queued, not running" do
    run = run_with_session("queued")

    states = BoardTaskResource.new(@task.reload).to_h["recentWorkflowRuns"].map { |r| r[:state] || r["state"] }

    assert_equal [ "queued" ], states,
      "the card would otherwise claim work is happening while it waits for capacity"
    assert_equal "running", run.reload.state, "the run's own state is untouched"
  end

  test "a run that is executing keeps its own state" do
    run_with_session("ready")

    states = BoardTaskResource.new(@task.reload).to_h["recentWorkflowRuns"].map { |r| r[:state] || r["state"] }

    assert_equal [ "running" ], states
  end

  # The board resolves this once for the whole page; a card handed the answer
  # must use it rather than asking again.
  test "a caller-supplied answer is used instead of querying per card" do
    run = run_with_session("ready")

    payload = BoardTaskResource.new(@task.reload, params: { waiting_runs: Set[run.id] }).to_h
    states = payload["recentWorkflowRuns"].map { |r| r[:state] || r["state"] }

    assert_equal [ "queued" ], states
  end
end
