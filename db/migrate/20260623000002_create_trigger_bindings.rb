# frozen_string_literal: true

# Generalized trigger registry. A TriggerBinding says "events of this type,
# matching this predicate, launch this workflow". It is the generalization of
# column_workflow_bindings (and task_waits) for NEW event sources such as Slack
# and arbitrary inbound webhooks. The two legacy sources keep their own tables
# and are routed through the same TriggerEngine.
class CreateTriggerBindings < ActiveRecord::Migration[8.1]
  def change
    create_table :trigger_bindings do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :workflow, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :name
      t.string :event_type, null: false
      t.jsonb :filter_predicate, null: false, default: {}
      t.string :trigger_mode, null: false, default: "auto"
      t.boolean :enabled, null: false, default: true
      t.integer :cooldown_seconds, null: false, default: 0

      t.timestamps
    end

    add_index :trigger_bindings, %i[project_id event_type enabled]
  end
end
