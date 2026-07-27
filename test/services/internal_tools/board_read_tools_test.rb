# frozen_string_literal: true

require "test_helper"

class InternalTools::BoardReadToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @col1 = create(:board_column, board: @board, name: "Backlog", position: 1, purpose: "New tasks")
    @col2 = create(:board_column, board: @board, name: "In Dev", position: 2, purpose: "Active dev")
    @task = create(:board_task, board: @board, board_column: @col1, title: "Test task", description: "Do something", tags: [ "frontend" ])

    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  # === board_list_tasks ===

  test "board_list_tasks returns all tasks" do
    result = InternalTools::BoardListTasks.new(params: {}, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "Test task", data.first["title"]
    assert_equal @task.id, data.first["id"]
  end

  test "board_list_tasks filters by column_name" do
    create(:board_task, board: @board, board_column: @col2, title: "Dev task")

    result = InternalTools::BoardListTasks.new(params: { column_name: "In Dev" }, session: @session).execute
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "Dev task", data.first["title"]
  end

  test "board_list_tasks filters by tag" do
    create(:board_task, board: @board, board_column: @col1, title: "Other task", tags: [ "backend" ])

    result = InternalTools::BoardListTasks.new(params: { tag: "frontend" }, session: @session).execute
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "Test task", data.first["title"]
  end

  test "board_list_tasks does not produce N+1 queries" do
    create_list(:board_task, 10, board: @board, board_column: @col1)

    query_count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if %w[BEGIN COMMIT ROLLBACK].include?(payload[:sql])
      query_count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      InternalTools::BoardListTasks.new(params: {}, session: @session).execute
    end

    assert_operator query_count, :<=, 8
  end

  # === board_get_task ===

  test "board_get_task returns full task details" do
    result = InternalTools::BoardGetTask.new(params: { task_id: @task.id }, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @task.id, data["id"]
    assert_equal "Test task", data["title"]
    assert_equal "Do something", data["description"]
    assert_equal @col1.id, data["boardColumnId"]
    assert data.key?("childrenCount")
    assert data.key?("commentsCount")
    assert data.key?("assetsCount")
  end

  test "board_get_task uses workflow_run board_task_id when no task_id param" do
    result = InternalTools::BoardGetTask.new(params: {}, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @task.id, data["id"]
  end

  test "board_get_task returns error for unknown task" do
    result = InternalTools::BoardGetTask.new(params: { task_id: 99999 }, session: @session).execute
    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Task not found"
  end

  # === board_get_comments ===

  test "board_get_comments returns comments for task" do
    create(:task_comment, board_task: @task, author: @user, body: "Looks good", tags: [ "review" ])
    create(:task_comment, board_task: @task, author: @user, body: "Agent note", author_type: :agent)

    result = InternalTools::BoardGetComments.new(params: { task_id: @task.id }, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 2, data.size
    assert data.first.key?("authorName")
    assert data.first.key?("authorType")
  end

  test "board_get_comments filters by tag" do
    create(:task_comment, board_task: @task, author: @user, body: "Tagged", tags: [ "tech_design" ])
    create(:task_comment, board_task: @task, author: @user, body: "Not tagged")

    result = InternalTools::BoardGetComments.new(params: { task_id: @task.id, tag: "tech_design" }, session: @session).execute
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "Tagged", data.first["body"]
  end

  test "board_get_comments filters by author_type" do
    create(:task_comment, board_task: @task, author: @user, body: "Human comment", author_type: :human)
    create(:task_comment, board_task: @task, author: @user, body: "Agent comment", author_type: :agent)

    result = InternalTools::BoardGetComments.new(params: { task_id: @task.id, author_type: "agent" }, session: @session).execute
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "Agent comment", data.first["body"]
  end

  # === board_get_task_assets ===

  test "board_get_task_assets returns assets" do
    create(:task_asset, board_task: @task, author: @user, name: "report.md", tags: [ "qa" ])

    result = InternalTools::BoardGetTaskAssets.new(params: { task_id: @task.id }, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "report.md", data.first["name"]
    assert data.first.key?("fileUrl")
  end

  test "board_get_task_assets filters by tag" do
    create(:task_asset, board_task: @task, author: @user, name: "qa.md", tags: [ "qa" ])
    create(:task_asset, board_task: @task, author: @user, name: "other.md", tags: [ "design" ])

    result = InternalTools::BoardGetTaskAssets.new(params: { task_id: @task.id, tag: "qa" }, session: @session).execute
    data = JSON.parse(result[:stdout])
    assert_equal 1, data.size
    assert_equal "qa.md", data.first["name"]
  end

  # === board_get_board_info ===

  test "board_get_board_info returns board with columns" do
    result = InternalTools::BoardGetBoardInfo.new(params: {}, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @board.id, data["id"]
    assert_equal @board.name, data["name"]
    assert_equal 2, data["boardColumns"].size
    assert_equal "Backlog", data["boardColumns"].first["name"]
    assert_equal "New tasks", data["boardColumns"].first["purpose"]
  end
end
