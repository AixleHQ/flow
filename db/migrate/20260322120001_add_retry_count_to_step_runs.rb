# frozen_string_literal: true

class AddRetryCountToStepRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :step_runs, :retry_count, :integer, null: false, default: 0
  end
end
