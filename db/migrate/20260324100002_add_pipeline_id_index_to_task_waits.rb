# frozen_string_literal: true

class AddPipelineIdIndexToTaskWaits < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE INDEX index_task_waits_on_metadata_pipeline_id
      ON task_waits (((metadata->>'pipeline_id')::bigint))
      WHERE wait_type = 'gitlab_pipeline_completed'
    SQL
  end

  def down
    remove_index :task_waits, name: "index_task_waits_on_metadata_pipeline_id"
  end
end
