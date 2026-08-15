# frozen_string_literal: true

require "test_helper"

class BoardActivityResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company, name: "Ada Lovelace")
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column, title: "Ship it")
  end

  test "workflow events describe the workflow and task, including cancellation" do
    descriptions = %w[workflow_started workflow_completed workflow_failed workflow_cancelled].map do |event_type|
      describe_activity(event_type, metadata: { "workflow_name" => "Nightly build" })
    end

    assert_equal [ "Workflow 'Nightly build' started on 'Ship it'",
                   "Workflow 'Nightly build' completed on 'Ship it'",
                   "Workflow 'Nightly build' failed on 'Ship it'",
                   "Workflow 'Nightly build' cancelled on 'Ship it'" ], descriptions
  end

  test "unmapped events fall back to a humanized actor sentence" do
    assert_equal "Ada Lovelace performed task archived",
                 describe_activity("task_archived", actor_type: :human)
  end

  private

  def describe_activity(event_type, actor_type: :system, metadata: {})
    activity = BoardActivity.create!(
      board: @board, board_task: @task, event_type:,
      actor: @user, actor_type:, metadata:
    )
    BoardActivityResource.new(activity).to_h["description"]
  end
end
