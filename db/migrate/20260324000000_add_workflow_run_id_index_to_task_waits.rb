# frozen_string_literal: true

class AddWorkflowRunIdIndexToTaskWaits < ActiveRecord::Migration[8.0]
  def change
    add_index :task_waits,
      "((metadata->>'run_id')::bigint)",
      name: "index_task_waits_on_metadata_run_id"
  end
end
