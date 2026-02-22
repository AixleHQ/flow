# frozen_string_literal: true

class AddFileDataToWorkflowRunAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :workflow_run_assets, :file_data, :jsonb
  end
end
