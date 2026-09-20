# frozen_string_literal: true

class AddYoutrackIntegration < ActiveRecord::Migration[8.0]
  def change
    add_reference :trigger_bindings, :integration, foreign_key: { on_delete: :nullify }

    create_table :external_resources do |t|
      t.references :board_task, null: false, foreign_key: { on_delete: :cascade }
      t.string :type, null: false
      t.string :external_instance, null: false
      t.string :external_id, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :external_resources, %i[board_task_id type external_instance external_id],
      unique: true, name: "idx_external_resources_unique"
    add_index :external_resources, %i[type external_instance external_id board_task_id],
      name: "idx_external_resources_lookup"
  end
end
