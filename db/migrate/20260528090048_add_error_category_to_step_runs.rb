# frozen_string_literal: true

class AddErrorCategoryToStepRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :step_runs, :error_category, :string
  end
end
