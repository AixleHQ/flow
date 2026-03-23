# frozen_string_literal: true

class AddCreatorAndMetadataIndexesToTaskWaits < ActiveRecord::Migration[7.2]
  def change
    add_reference :task_waits, :creator, foreign_key: { to_table: :users }, null: true

    add_index :task_waits, "(metadata->>'repo_full_name')",
              name: "index_task_waits_on_metadata_repo_full_name",
              using: :btree

    add_index :task_waits, "((metadata->>'pr_number')::int)",
              name: "index_task_waits_on_metadata_pr_number",
              using: :btree
  end
end
