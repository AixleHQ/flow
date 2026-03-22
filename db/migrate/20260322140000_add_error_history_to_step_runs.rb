# frozen_string_literal: true

class AddErrorHistoryToStepRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :step_runs, :error_history, :jsonb, null: false, default: []
  end
end
