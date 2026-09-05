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

  def list_tasks(**params)
    result = InternalTools::BoardListTasks.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code]
    JSON.parse(result[:stdout])
  end

  test "board_list_tasks returns a page of tasks with the board's total" do
    data = list_tasks
    assert_equal 1, data["total"]
    assert_equal 0, data["offset"]
    assert_equal InternalTools::BoardListTasks::DEFAULT_LIMIT, data["limit"]
    assert_equal false, data["has_more"] # rubocop:disable Minitest/RefuteFalse
    assert_equal 1, data["tasks"].size
    assert_equal "Test task", data["tasks"].first["title"]
    assert_equal @task.id, data["tasks"].first["id"]
  end

  test "board_list_tasks omits descriptions and points at board_get_task instead" do
    row = list_tasks["tasks"].first

    assert_not row.key?("description")
    # Everything a card needs to be read without the description is still there.
    assert_equal [ "frontend" ], row["tags"]
    assert_equal 0, row["comments_count"]
    assert_equal [], row["pending_gates"]
  end

  test "board_list_tasks pages through the board in a stable column-then-position order" do
    # A second column's tasks reuse positions 1..n, which is what an unstable
    # order would interleave differently on every page.
    second = create(:board_task, board: @board, board_column: @col1, title: "Second")
    third = create(:board_task, board: @board, board_column: @col2, title: "Third")

    first_page = list_tasks(limit: 2)
    assert_equal [ @task.title, second.title ], first_page["tasks"].map { |t| t["title"] }
    assert_equal 3, first_page["total"]
    assert first_page["has_more"]

    second_page = list_tasks(limit: 2, offset: 2)
    assert_equal [ third.title ], second_page["tasks"].map { |t| t["title"] }
    assert_equal 3, second_page["total"]
    assert_equal false, second_page["has_more"] # rubocop:disable Minitest/RefuteFalse
  end

  test "board_list_tasks caps the page size and floors the offset" do
    data = list_tasks(limit: 5_000, offset: -10)

    assert_equal InternalTools::BoardListTasks::MAX_LIMIT, data["limit"]
    assert_equal 0, data["offset"]
  end

  test "board_list_tasks counts the whole filtered set, not the page" do
    create_list(:board_task, 4, board: @board, board_column: @col2, tags: [ "frontend" ])

    data = list_tasks(tag: "frontend", limit: 2)

    assert_equal 5, data["total"]
    assert_equal 2, data["tasks"].size
    assert data["has_more"]
  end

  test "board_list_tasks filters by column_name" do
    create(:board_task, board: @board, board_column: @col2, title: "Dev task")

    data = list_tasks(column_name: "In Dev")
    assert_equal 1, data["total"]
    assert_equal [ "Dev task" ], data["tasks"].map { |t| t["title"] }
  end

  test "board_list_tasks filters by tag" do
    create(:board_task, board: @board, board_column: @col1, title: "Other task", tags: [ "backend" ])

    data = list_tasks(tag: "frontend")
    assert_equal [ "Test task" ], data["tasks"].map { |t| t["title"] }
  end

  # The budget is what makes this a guard rather than a snapshot: it must stay
  # flat as tasks are added, and each raise needs a reason.
  #
  # 8 -> 9 with the session queue: a run whose step is waiting for a slot has to
  # read as `queued` on the card, and the runs that are waiting are resolved in
  # ONE query for the whole page. Asking per task is the shape this test exists
  # to forbid.
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

    assert_operator query_count, :<=, 9
  end

  # === board_get_task ===

  test "board_get_task returns full task details" do
    result = InternalTools::BoardGetTask.new(params: { task_id: @task.id }, session: @session).execute
    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @task.id, data["id"]
    assert_equal "Test task", data["title"]
    assert_equal "Do something", data["description"]
    assert_equal @col1.id, data["board_column_id"]
    assert data.key?("children_count")
    assert data.key?("comments_count")
    assert data.key?("assets_count")
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
    assert data.first.key?("author_name")
    assert data.first.key?("author_type")
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
    assert data.first.key?("file_url")
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
    assert_equal 2, data["board_columns"].size
    assert_equal "Backlog", data["board_columns"].first["name"]
    assert_equal "New tasks", data["board_columns"].first["purpose"]
  end
end
