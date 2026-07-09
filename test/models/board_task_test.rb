# frozen_string_literal: true

require "test_helper"

class BoardTaskTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Board", project: @project)
    @col1 = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @col2 = BoardColumn.create!(name: "Done", board: @board, position: 2)
  end

  # == Validations ==

  test "valid with all required fields" do
    task = BoardTask.new(title: "My task", board: @board, board_column: @col1)
    assert task.valid?
  end

  test "invalid without title" do
    task = BoardTask.new(board: @board, board_column: @col1)
    refute_predicate task, :valid?
    assert task.errors[:title].present?
  end

  test "invalid when column from different board" do
    other_project = create(:project, company: @company, owner: @owner)
    other_board = Board.create!(name: "Other", project: other_project)
    other_col = BoardColumn.create!(name: "X", board: other_board, position: 1)

    task = BoardTask.new(title: "Bad", board: @board, board_column: other_col)
    refute_predicate task, :valid?
    assert task.errors[:board_column].present?
  end

  # == Auto-position ==

  test "auto-assigns position on create" do
    t1 = BoardTask.create!(title: "A", board: @board, board_column: @col1)
    t2 = BoardTask.create!(title: "B", board: @board, board_column: @col1)

    assert_equal 1, t1.position
    assert_equal 2, t2.position
  end

  test "position scoped to column" do
    t1 = BoardTask.create!(title: "A", board: @board, board_column: @col1)
    t2 = BoardTask.create!(title: "B", board: @board, board_column: @col2)

    assert_equal 1, t1.position
    assert_equal 1, t2.position
  end

  # == Enumerize ==

  test "task_type defaults to not_specified" do
    task = BoardTask.create!(title: "X", board: @board, board_column: @col1)
    assert_equal "not_specified", task.task_type
  end

  test "priority can be nil" do
    task = BoardTask.create!(title: "X", board: @board, board_column: @col1)
    assert_nil task.priority
  end

  test "task_type validates allowed values" do
    task = BoardTask.new(title: "X", board: @board, board_column: @col1)
    task.task_type = :epic
    assert task.valid?
  end

  # == Tags ==

  test "tags default to empty array" do
    task = BoardTask.create!(title: "X", board: @board, board_column: @col1)
    assert_equal [], task.tags
  end

  test "tags can store values" do
    task = BoardTask.create!(title: "X", board: @board, board_column: @col1, tags: %w[urgent frontend])
    assert_equal %w[urgent frontend], task.reload.tags
  end

  test "with_tag scope filters by tag" do
    BoardTask.create!(title: "A", board: @board, board_column: @col1, tags: %w[urgent])
    BoardTask.create!(title: "B", board: @board, board_column: @col1, tags: %w[backend])

    assert_equal 1, BoardTask.with_tag("urgent").count
    assert_equal "A", BoardTask.with_tag("urgent").first.title
  end

  # == Associations ==

  test "destroying board destroys tasks" do
    BoardTask.create!(title: "A", board: @board, board_column: @col1)

    assert_difference("BoardTask.count", -1) do
      @board.destroy
    end
  end

  test "column with tasks prevents destruction" do
    BoardTask.create!(title: "A", board: @board, board_column: @col1)
    refute @col1.destroy
    assert @col1.errors[:base].present?
  end

  # == Ransack ==

  test "ransackable_attributes returns expected fields" do
    attrs = BoardTask.ransackable_attributes
    assert_includes attrs, "title"
    assert_includes attrs, "task_type"
    assert_includes attrs, "priority"
    assert_includes attrs, "assignee_id"
  end

  # == 21.2: Hierarchy Validations ==

  test "parent task must be epic" do
    epic = BoardTask.create!(title: "Epic", board: @board, board_column: @col1, task_type: :epic)
    story = BoardTask.new(title: "Story", board: @board, board_column: @col1, parent_task: epic)
    assert story.valid?
  end

  test "parent task that is not epic is rejected" do
    non_epic = BoardTask.create!(title: "Bug", board: @board, board_column: @col1, task_type: :bug)
    task = BoardTask.new(title: "Child", board: @board, board_column: @col1, parent_task: non_epic)
    refute_predicate task, :valid?
    assert task.errors[:parent_task].present?
  end

  test "parent task must belong to same board" do
    other_project = create(:project, company: @company, owner: @owner)
    other_board = Board.create!(name: "Other", project: other_project)
    other_col = BoardColumn.create!(name: "X", board: other_board, position: 1)
    other_epic = BoardTask.create!(title: "Epic", board: other_board, board_column: other_col, task_type: :epic)

    task = BoardTask.new(title: "Child", board: @board, board_column: @col1, parent_task: other_epic)
    refute_predicate task, :valid?
    assert_includes task.errors[:parent_task], "must belong to the same board"
  end

  test "max one level nesting" do
    epic = BoardTask.create!(title: "Epic", board: @board, board_column: @col1, task_type: :epic)
    story = BoardTask.create!(title: "Story", board: @board, board_column: @col1, parent_task: epic, task_type: :epic)
    grandchild = BoardTask.new(title: "GC", board: @board, board_column: @col1, parent_task: story)
    refute_predicate grandchild, :valid?
    assert_includes grandchild.errors[:parent_task], "cannot nest more than one level deep"
  end

  test "deleting epic nullifies children parent_task_id" do
    epic = BoardTask.create!(title: "Epic", board: @board, board_column: @col1, task_type: :epic)
    story = BoardTask.create!(title: "Story", board: @board, board_column: @col1, parent_task: epic)

    epic.destroy
    story.reload
    assert_nil story.parent_task_id
  end

  # == 21.3: Assignee Validation ==

  test "assignee must be project member" do
    outsider = create(:user, :employee, company: @company)
    task = BoardTask.new(title: "T", board: @board, board_column: @col1, assignee: outsider)
    refute_predicate task, :valid?
    assert task.errors[:assignee].present?
  end

  test "assignee can be owner" do
    task = BoardTask.new(title: "T", board: @board, board_column: @col1, assignee: @owner)
    assert task.valid?
  end

  test "assignee can be collaborator" do
    collaborator = create(:user, :employee, company: @company)
    @project.add_collaborator(collaborator)
    task = BoardTask.new(title: "T", board: @board, board_column: @col1, assignee: collaborator)
    assert task.valid?
  end

  test "unassigned task is valid" do
    task = BoardTask.new(title: "T", board: @board, board_column: @col1, assignee_id: nil)
    assert task.valid?
  end

  # == Archiving ==

  test "archived? reflects archived_at" do
    task = BoardTask.create!(title: "T", board: @board, board_column: @col1)
    refute_predicate task, :archived?

    task.update!(archived_at: Time.current)
    assert_predicate task, :archived?
  end

  test "active scope excludes archived tasks and archived scope includes only them" do
    active = BoardTask.create!(title: "Active", board: @board, board_column: @col1)
    archived = BoardTask.create!(title: "Archived", board: @board, board_column: @col1, archived_at: Time.current)

    assert_includes BoardTask.active, active
    assert_not_includes BoardTask.active, archived
    assert_includes BoardTask.archived, archived
    assert_not_includes BoardTask.archived, active
  end
end
