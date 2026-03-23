# frozen_string_literal: true

require "test_helper"

class InternalTools::BoardWriteToolsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @col1 = create(:board_column, board: @board, name: "Backlog", position: 1)
    @col2 = create(:board_column, board: @board, name: "In Dev", position: 2)
    @col3 = create(:board_column, board: @board, name: "QA", position: 3)
    @task = create(:board_task, board: @board, board_column: @col1, title: "Test task")

    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    @step_run = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  # === board_create_task ===

  test "board_create_task creates task in specified column" do
    result = InternalTools::BoardCreateTask.new(
      params: { title: "New task", description: "Something to do", column_name: "In Dev" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "New task", data["title"]
    assert_equal "In Dev", data["column"]
  end

  test "board_create_task defaults to first column" do
    result = InternalTools::BoardCreateTask.new(
      params: { title: "Default column task" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "Backlog", data["column"]
  end

  test "board_create_task returns error for unknown column" do
    result = InternalTools::BoardCreateTask.new(
      params: { title: "Task", column_name: "Nonexistent" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  # === board_update_task ===

  test "board_update_task updates specified fields" do
    result = InternalTools::BoardUpdateTask.new(
      params: { task_id: @task.id, title: "Updated title", priority: "high" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @task.reload
    assert_equal "Updated title", @task.title
    assert_equal "high", @task.priority
  end

  test "board_update_task returns error when no valid fields" do
    result = InternalTools::BoardUpdateTask.new(
      params: { task_id: @task.id },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "No valid fields"
  end

  test "board_update_task returns error for unknown task" do
    result = InternalTools::BoardUpdateTask.new(
      params: { task_id: 99999, title: "X" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Task not found"
  end

  # === board_move_task ===

  test "board_move_task moves task to target column" do
    TemporalService.stubs(:start_workflow)
    TemporalService.stubs(:send_signal)
    TemporalService.stubs(:cancel_workflow)

    result = InternalTools::BoardMoveTask.new(
      params: { task_id: @task.id, column_name: "In Dev" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @task.reload
    assert_equal @col2.id, @task.board_column_id
  end

  test "board_move_task returns error for unknown column" do
    result = InternalTools::BoardMoveTask.new(
      params: { task_id: @task.id, column_name: "Nonexistent" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  # === board_add_comment ===

  test "board_add_comment creates comment on task" do
    result = InternalTools::BoardAddComment.new(
      params: { task_id: @task.id, body: "Implementation complete", tags: [ "change_log" ] },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert data["id"].present?

    comment = TaskComment.find(data["id"])
    assert_equal "Implementation complete", comment.body
    assert_equal "agent", comment.author_type
    assert_includes comment.tags, "change_log"
  end

  test "board_add_comment uses workflow_run user as fallback author" do
    result = InternalTools::BoardAddComment.new(
      params: { task_id: @task.id, body: "Note" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    comment = TaskComment.last
    assert_equal @user.id, comment.author_id
  end

  # === board_attach_asset ===

  test "board_attach_asset creates asset from file_path in container" do
    @session.update!(container_id: "test-container-123")

    runtime = mock("runtime")
    runtime.expects(:read_file).with("test-container-123", "/workspace/outputs/screenshot.png")
      .returns("fake-png-binary-content")
    ContainerRuntime.stubs(:build).returns(runtime)

    result = InternalTools::BoardAttachAsset.new(
      params: { task_id: @task.id, file_path: "/workspace/outputs/screenshot.png", name: "qa-desktop.png", tags: [ "qa", "desktop" ] },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal "qa-desktop.png", data["name"]
  end

  test "board_attach_asset returns error when file not found in container" do
    @session.update!(container_id: "test-container-123")

    runtime = mock("runtime")
    runtime.expects(:read_file).returns(nil)
    ContainerRuntime.stubs(:build).returns(runtime)

    result = InternalTools::BoardAttachAsset.new(
      params: { task_id: @task.id, file_path: "/workspace/outputs/missing.png", name: "missing.png" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/File not found/, result[:stderr])
  end

  test "board_attach_asset returns error when no container and file_path used" do
    @session.update!(container_id: nil)

    result = InternalTools::BoardAttachAsset.new(
      params: { task_id: @task.id, file_path: "/workspace/outputs/screenshot.png", name: "screenshot.png" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/No container/, result[:stderr])
  end

  test "board_attach_asset returns error when file_path missing" do
    result = InternalTools::BoardAttachAsset.new(
      params: { task_id: @task.id, name: "nothing.png" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/file_path is required/, result[:stderr])
  end

  # === board_manage_tags ===

  test "board_manage_tags adds tag to task" do
    result = InternalTools::BoardManageTags.new(
      params: { action: "add", entity_type: "task", entity_id: @task.id, tag: "urgent" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @task.reload
    assert_includes @task.tags, "urgent"
  end

  test "board_manage_tags removes tag from task" do
    @task.update!(tags: [ "frontend", "urgent" ])

    result = InternalTools::BoardManageTags.new(
      params: { action: "remove", entity_type: "task", entity_id: @task.id, tag: "urgent" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @task.reload
    assert_not_includes @task.tags, "urgent"
    assert_includes @task.tags, "frontend"
  end

  test "board_manage_tags adds tag to comment" do
    comment = create(:task_comment, board_task: @task, author: @user, body: "Note", tags: [])

    result = InternalTools::BoardManageTags.new(
      params: { action: "add", entity_type: "comment", entity_id: comment.id, tag: "tech_design" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    comment.reload
    assert_includes comment.tags, "tech_design"
  end

  test "board_manage_tags returns error for invalid action" do
    result = InternalTools::BoardManageTags.new(
      params: { action: "delete", entity_type: "task", entity_id: @task.id, tag: "x" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "add"
  end

  test "board_manage_tags returns error for invalid entity_type" do
    result = InternalTools::BoardManageTags.new(
      params: { action: "add", entity_type: "board", entity_id: 1, tag: "x" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "task"
  end
end
