# frozen_string_literal: true

require "test_helper"

class BoardContextResolverTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board, position: 1)
    @task = create(:board_task, board: @board, board_column: @column)

    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  test "resolves board from workflow_run board_task" do
    board = BoardContextResolver.resolve(@session)
    assert_equal @board, board
  end

  test "resolves board from project when no board_task" do
    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: nil)
    sr = create(:step_run, workflow_run: run, step: step)

    session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, initial_prompt: "do work")
    sr.update!(terminal_session: session)
    session.reload

    board = BoardContextResolver.resolve(session)
    assert_equal @board, board
  end

  test "returns nil when no board exists" do
    project_no_board = create(:project, company: @company, owner: @user)
    session = create(:terminal_session, :running, :agent_session,
      user: @user, project: project_no_board, initial_prompt: "do work")

    board = BoardContextResolver.resolve(session)
    assert_nil board
  end
end
