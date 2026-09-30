# frozen_string_literal: true

class CreateTrackerTables < ActiveRecord::Migration[8.1]
  def change
    create_table :project_trackers do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_scope_id, null: false
      t.string :external_scope_key
      t.string :name, null: false
      t.string :handle, null: false
      t.boolean :primary, null: false, default: false
      t.string :access, null: false, default: "read_write"
      t.string :status, null: false, default: "active"
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :project_trackers, %i[project_id integration_id external_scope_id], unique: true,
      name: "idx_project_trackers_scope"
    add_index :project_trackers, %i[project_id handle], unique: true, name: "idx_project_trackers_handle"
    add_index :project_trackers, :project_id, unique: true, where: '"primary"', name: "idx_project_trackers_one_primary"

    # No foreign keys on the session, user and run columns, like azure_devops_operations:
    # the ledger outlives the rows it mentions, and it must never block their deletion.
    create_table :tracker_operations do |t|
      t.references :project_tracker, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :operation, null: false
      t.string :operation_key, null: false
      t.string :request_digest, null: false
      t.string :state, null: false, default: "pending"
      t.string :error_code
      t.string :issue_id
      t.jsonb :change, null: false, default: {}
      t.string :result_ref
      t.jsonb :result, null: false, default: {}
      t.bigint :terminal_session_id
      t.bigint :user_id
      t.bigint :workflow_run_id
      t.bigint :workflow_id
      t.jsonb :chain, null: false, default: []
      t.timestamps
    end
    add_index :tracker_operations, %i[project_tracker_id operation_key], unique: true,
      name: "idx_tracker_operations_key"
    add_index :tracker_operations, %i[project_tracker_id issue_id created_at], name: "idx_tracker_operations_issue"

    create_table :external_resources do |t|
      t.references :board_task, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :provider, null: false
      t.string :instance, null: false
      t.string :external_id, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :external_resources, %i[board_task_id kind provider instance external_id], unique: true,
      name: "idx_external_resources_unique"
    add_index :external_resources, %i[kind provider instance external_id], name: "idx_external_resources_identity"
  end
end
