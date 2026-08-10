# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class TriggerTaskWorkflowTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @board = create(:board, project: @project)
      @column = create(:board_column, board: @board)
      @workflow = create(:workflow, scope: @project)
      @task = create(:board_task, board: @board, board_column: @column)
      @binding = ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow,
                                               trigger_mode: :manual, cooldown_seconds: 0)
      # TemporalService is the app-owned boundary (docs/testing.md §4): cancelling a
      # run signals its execution, and the real WorkflowService is what we want to
      # exercise underneath.
      TemporalService.stubs(:send_signal).returns({ ok: true })
    end

    def execute(actor: @user, **params)
      TriggerTaskWorkflow.new(params: { project_id: @project.id, task_id: @task.id, **params }, user: actor).execute
    end

    def payload(result) = JSON.parse(result[:stdout])

    # WorkflowService.start is where the trigger engine hands off to the container
    # machinery. The run it returns is a real row so the tool's own payload is
    # exercised — and it is deliberately NOT linked to the task, because linking it
    # would make the fixture itself the "run already in flight" the tool refuses.
    def stub_started_run
      run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "pending")
      WorkflowService.stubs(:start).returns(run)
      run
    end

    test "triggers the column's workflow the way the task card's button does" do
      run = stub_started_run

      body = payload(execute)

      assert_equal run.id, body["run_id"]
      assert_equal @task.id, body["task_id"]
      assert_nil body["cancelled_run_id"]
    end

    test "a task with a run already in flight is refused, naming the run" do
      blocking = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                        board_task_id: @task.id, state: "running")

      result = execute

      assert_equal 1, result[:exit_code]
      assert_match(/#{blocking.id} is running/, result[:stderr])
      assert_match(/force: true/, result[:stderr])
    end

    test "force cancels the in-flight run, then triggers a fresh one" do
      blocking = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                        board_task_id: @task.id, state: "running")
      started = stub_started_run

      body = payload(execute(force: true))

      assert_equal blocking.id, body["cancelled_run_id"]
      assert_equal started.id, body["run_id"]
      # The real WorkflowService ran: the blocking run is cancelled, which is also
      # what clears TaskService's own "active run already exists" guard.
      assert_equal "cancelled", blocking.reload.state
    end

    test "a column with no binding is refused" do
      @binding.destroy!
      @column.reload

      result = execute

      assert_equal 1, result[:exit_code]
      assert_match(/No workflow binding/, result[:stderr])
    end

    test "a task from another project is not found" do
      stranger = create(:user, :with_company)
      other_project = create(:project, owner: stranger, company: stranger.companies.first)
      other_board = create(:board, project: other_project)
      other_task = create(:board_task, board: other_board,
                          board_column: create(:board_column, board: other_board))

      result = execute(task_id: other_task.id)

      assert_equal 1, result[:exit_code]
      assert_match(/not found in this project/, result[:stderr])
    end

    test "a read-only member cannot trigger" do
      viewer = create(:user)
      create(:company_membership, user: viewer, company: @company, role: :viewer)
      create(:project_collaborator, project: @project, user: viewer)

      assert_raises(PersonalTools::Base::UnauthorizedError) { execute(actor: viewer) }
    end
  end
end
