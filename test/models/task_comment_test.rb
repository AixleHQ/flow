# frozen_string_literal: true

require "test_helper"

class TaskCommentTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Task", board: @board, board_column: @col)
  end

  test "valid with all required fields" do
    comment = TaskComment.new(body: "Hello", board_task: @task, author: @owner)
    assert comment.valid?
  end

  test "invalid without body" do
    comment = TaskComment.new(board_task: @task, author: @owner)
    refute_predicate comment, :valid?
    assert comment.errors[:body].present?
  end

  test "invalid without author" do
    comment = TaskComment.new(body: "Hello", board_task: @task)
    refute_predicate comment, :valid?
  end

  test "sets created_at on create" do
    comment = TaskComment.create!(body: "Test", board_task: @task, author: @owner)
    assert_not_nil comment.created_at
  end

  test "does not have updated_at column" do
    refute_includes TaskComment.column_names, "updated_at"
  end

  test "author_type defaults to human" do
    comment = TaskComment.create!(body: "Test", board_task: @task, author: @owner)
    assert_equal "human", comment.author_type
  end

  test "author_type can be agent" do
    comment = TaskComment.new(body: "Test", board_task: @task, author: @owner, author_type: :agent)
    assert comment.valid?
    assert_equal "agent", comment.author_type
  end

  test "tags default to empty array" do
    comment = TaskComment.create!(body: "Test", board_task: @task, author: @owner)
    assert_equal [], comment.tags
  end

  test "tags can store values" do
    comment = TaskComment.create!(body: "Test", board_task: @task, author: @owner, tags: %w[feedback])
    assert_equal %w[feedback], comment.reload.tags
  end

  test "with_tag scope" do
    TaskComment.create!(body: "A", board_task: @task, author: @owner, tags: %w[bug])
    TaskComment.create!(body: "B", board_task: @task, author: @owner, tags: %w[feature])

    assert_equal 1, TaskComment.with_tag("bug").count
  end

  test "by_author_type scope" do
    TaskComment.create!(body: "A", board_task: @task, author: @owner, author_type: :human)
    TaskComment.create!(body: "B", board_task: @task, author: @owner, author_type: :agent)

    assert_equal 1, TaskComment.by_author_type(:agent).count
  end

  test "destroying task destroys comments" do
    TaskComment.create!(body: "A", board_task: @task, author: @owner)

    assert_difference("TaskComment.count", -1) do
      @task.reload.destroy
    end
  end

  test "board_task_resource returns correct comments_count" do
    TaskComment.create!(body: "A", board_task: @task, author: @owner)
    TaskComment.create!(body: "B", board_task: @task, author: @owner)

    result = BoardTaskResource.new(@task.reload).to_h
    assert_equal 2, result["commentsCount"]
  end
end
