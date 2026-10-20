# frozen_string_literal: true

# Files moving between tracker issues and board tasks
# (docs/design/tracker-attachments.md §5.2).
class CreateTrackerAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assets, :source, :string, null: false, default: "upload"
    add_column :task_assets, :content_sha256, :string
    reversible do |dir|
      dir.up { execute "UPDATE task_assets SET source = 'agent' WHERE author_type = 'agent'" }
    end

    add_column :trigger_bindings, :copy_attachments, :boolean, null: false, default: false

    # No foreign key on the ledger row, like tracker_operations' own run columns:
    # the record of what is on an issue outlives the write that put it there.
    create_table :tracker_attachments do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :provider, null: false
      t.string :instance, null: false
      t.string :issue_id, null: false
      t.string :external_id, null: false
      t.string :direction, null: false
      t.string :content_sha256, null: false
      t.references :task_asset, foreign_key: { on_delete: :nullify }
      t.bigint :tracker_operation_id
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :tracker_attachments, %i[project_id provider instance issue_id external_id], unique: true,
      name: "idx_tracker_attachments_identity"
    add_index :tracker_attachments, %i[project_id provider instance issue_id content_sha256],
      name: "idx_tracker_attachments_content"
  end
end
