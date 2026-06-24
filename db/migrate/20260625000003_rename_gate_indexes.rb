# frozen_string_literal: true

# Renaming task_waits -> gates (20260623000007) left the table's indexes with
# their old index_task_waits_on_* names. Rename them to match the new table.
class RenameGateIndexes < ActiveRecord::Migration[8.1]
  RENAMES = {
    "index_task_waits_on_metadata_pipeline_id"   => "index_gates_on_metadata_pipeline_id",
    "index_task_waits_on_metadata_pr_number"     => "index_gates_on_metadata_pr_number",
    "index_task_waits_on_metadata_run_id"        => "index_gates_on_metadata_run_id",
    "index_task_waits_on_metadata_repo_full_name" => "index_gates_on_metadata_repo_full_name"
  }.freeze

  def up
    RENAMES.each { |old_name, new_name| rename_index :gates, old_name, new_name }
  end

  def down
    RENAMES.each { |old_name, new_name| rename_index :gates, new_name, old_name }
  end
end
