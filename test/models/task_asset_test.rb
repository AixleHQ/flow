# frozen_string_literal: true

require "test_helper"

class TaskAssetTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Task", board: @board, board_column: @col)
  end

  test "valid with all required fields" do
    asset = TaskAsset.new(name: "doc.pdf", board_task: @task, author: @owner)
    assert asset.valid?
  end

  test "invalid without name" do
    asset = TaskAsset.new(board_task: @task, author: @owner)
    refute asset.valid?
    assert asset.errors[:name].present?
  end

  test "invalid without author" do
    asset = TaskAsset.new(name: "doc.pdf", board_task: @task)
    refute asset.valid?
  end

  test "author_type defaults to human" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @owner)
    assert_equal "human", asset.author_type
  end

  test "tags default to empty array" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @owner)
    assert_equal [], asset.tags
  end

  test "tags can store values" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @owner, tags: %w[design])
    assert_equal %w[design], asset.reload.tags
  end

  test "with_tag scope" do
    TaskAsset.create!(name: "a.pdf", board_task: @task, author: @owner, tags: %w[design])
    TaskAsset.create!(name: "b.pdf", board_task: @task, author: @owner, tags: %w[code])

    assert_equal 1, TaskAsset.with_tag("design").count
  end

  test "destroying task destroys assets" do
    TaskAsset.create!(name: "a.pdf", board_task: @task, author: @owner)

    assert_difference("TaskAsset.count", -1) do
      @task.destroy
    end
  end

  test "board_task_serializer returns correct assets_count" do
    TaskAsset.create!(name: "a.pdf", board_task: @task, author: @owner)
    TaskAsset.create!(name: "b.pdf", board_task: @task, author: @owner)

    serializer = BoardTaskSerializer.new(@task)
    assert_equal 2, serializer.assets_count
  end
end
