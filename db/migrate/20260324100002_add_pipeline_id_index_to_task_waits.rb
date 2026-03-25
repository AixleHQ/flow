# frozen_string_literal: true

class AddPipelineIdIndexToTaskWaits < ActiveRecord::Migration[8.0]
  def up
    add_index :task_waits,
              "(metadata->>'pipeline_id')::bigint",
              where: "wait_type = 'gitlab_pipeline_completed'",
              name: "index_task_waits_on_metadata_pipeline_id"
  end

  def down
    remove_index :task_waits, name: "index_task_waits_on_metadata_pipeline_id"
  end
end
