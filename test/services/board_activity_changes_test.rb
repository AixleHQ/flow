# frozen_string_literal: true

require "test_helper"

class BoardActivityChangesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company, name: "Ada Lovelace")
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column, title: "Ship it")
  end

  test "names each changed field once, the two assignee columns as one" do
    changes = changes_of("title" => %w[A B], "assignee_id" => [ @user.id, nil ], "assignee_team_id" => [ nil, 5 ],
                         "custom_flag" => [ false, true ])

    assert_equal [ "Title", "Assignee", "Custom flag" ], changes.labels
  end

  test "turns ids and enum values into what a person reads" do
    team = create(:project_team, project: @project, name: "Night shift")
    epic = create(:board_task, board: @board, board_column: @column, task_type: :epic, title: "Billing")

    entries = changes_of(
      "assignee_id" => [ @user.id, nil ], "assignee_team_id" => [ nil, team.id ],
      "parent_task_id" => [ nil, epic.id ], "task_type" => %w[not_specified bug],
      "tags" => [ [ "a" ], %w[a b] ], "description" => [ "", "New text" ]
    ).entries

    assert_equal [
      { field: "assignee", label: "Assignee", before: "Ada Lovelace", after: "Night shift" },
      { field: "parent_task_id", label: "Parent epic", before: nil, after: "##{epic.number} Billing" },
      { field: "task_type", label: "Type", before: "Not specified", after: "Bug" },
      { field: "tags", label: "Tags", before: "a", after: "a, b" },
      { field: "description", label: "Description", before: nil, after: "New text" }
    ], entries
  end

  test "names what no longer exists as deleted" do
    entries = changes_of("assignee_id" => [ 0, nil ], "parent_task_id" => [ 0, nil ]).entries

    assert_equal [ "Deleted user", "Deleted task" ], entries.map { |entry| entry[:before] }
  end

  test "has nothing for an activity that is not an edit, or one recorded without values" do
    moved = BoardActivity.create!(board: @board, board_task: @task, actor_type: :system, event_type: :task_moved,
                                  metadata: { "changes" => { "title" => %w[A B] } })

    assert_empty BoardActivityChanges.new(moved).entries
    assert_empty changes_of(nil).labels
  end

  private

  def changes_of(changes)
    metadata = changes.nil? ? {} : { "changes" => changes }
    BoardActivityChanges.new(BoardActivity.create!(board: @board, board_task: @task, actor: @user, actor_type: :human,
                                                   event_type: :task_updated, metadata: metadata))
  end
end
