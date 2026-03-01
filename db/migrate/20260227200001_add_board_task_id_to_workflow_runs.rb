# frozen_string_literal: true

class AddBoardTaskIdToWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    add_reference :workflow_runs, :board_task, null: true, foreign_key: true, index: true
  end
end
