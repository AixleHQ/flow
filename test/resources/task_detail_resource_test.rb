# frozen_string_literal: true

require "test_helper"

class TaskDetailResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @epic = create(:board_task, board: @board, board_column: @column, task_type: :epic, title: "Checkout revamp")
  end

  test "child_tasks names an epic's children in board order" do
    second = create(:board_task, board: @board, board_column: @column, parent_task: @epic,
      title: "Add card form", task_type: :story, position: 2)
    first = create(:board_task, board: @board, board_column: @column, parent_task: @epic,
      title: "Add address form", task_type: :bug, position: 1)

    children = TaskDetailResource.new(@epic.reload).to_h["childTasks"]

    assert_equal [ { "id" => first.id, "title" => "Add address form", "taskType" => "bug" },
                   { "id" => second.id, "title" => "Add card form", "taskType" => "story" } ], children
  end

  test "the agent-facing payload keeps the children in the Ruby spelling" do
    child = create(:board_task, board: @board, board_column: @column, parent_task: @epic,
      title: "Add card form", task_type: :story, position: 1)

    children = TaskDetailResource.new(@epic.reload, params: { snake_keys: true }).to_h["child_tasks"]

    assert_equal [ { id: child.id, title: "Add card form", task_type: "story" } ], children
  end

  test "a task without children serializes an empty child list" do
    task = create(:board_task, board: @board, board_column: @column)

    assert_equal [], TaskDetailResource.new(task).to_h["childTasks"]
  end
end
