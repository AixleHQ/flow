# frozen_string_literal: true

class CreateProjectMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :memory_enabled, :boolean, default: false, null: false
    create_table :project_memories do |t|
      t.references :project, null: false, foreign_key: true
      t.references :terminal_session, foreign_key: { on_delete: :nullify }
      t.string :title, null: false
      t.text :content, null: false
      t.string :topic_key, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :sources, null: false, default: []
      t.text :evidence
      t.datetime :validated_at
      t.datetime :review_at
      t.string :engram_id
      t.uuid :revision, null: false
      t.timestamps
    end
    add_index :project_memories, :revision, unique: true
    add_index :project_memories, [ :project_id, :topic_key, :state ]
    add_index :project_memories, [ :project_id, :engram_id ], unique: true
    add_check_constraint :project_memories, "state IN ('pending', 'validated', 'obsolete')", name: "project_memories_state"

    create_table :memory_retrievals do |t|
      t.references :project, null: false, foreign_key: true
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }
      t.references :project_memory, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :revision, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :kind, null: false
      t.timestamps
    end
  end
end
