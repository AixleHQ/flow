# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261016150000_decode_html_entities_in_labels")

class DecodeHtmlEntitiesInLabelsTest < ActiveSupport::TestCase
  def migrate
    migration = DecodeHtmlEntitiesInLabels.new
    migration.suppress_messages { migration.up }
  end

  test "escaped step, sub-step and task labels are decoded; instructions and plain labels are not touched" do
    step = create(:step)
    step.update_columns(name: "Plan &amp; release next batch", instructions: "Never write `&lt;div&gt;`.")
    sub_step = create(:sub_step, step: step)
    sub_step.update_columns(name: "Update &amp; promote sprint-status.yaml")
    plain = create(:step, workflow: step.workflow, name: "Review diff & route")
    board = Board.create!(name: "Board", project: step.workflow.scope)
    column = BoardColumn.create!(name: "Backlog", board: board, position: 1)
    task = BoardTask.create!(title: "placeholder", board: board, board_column: column)
    task.update_columns(title: "Correction history &amp; staff-review flag")

    migrate
    migrate

    assert_equal "Plan & release next batch", step.reload.name
    assert_equal "Never write `&lt;div&gt;`.", step.instructions
    assert_equal "Update & promote sprint-status.yaml", sub_step.reload.name
    assert_equal "Review diff & route", plain.reload.name
    assert_equal "Correction history & staff-review flag", task.reload.title
  end
end
