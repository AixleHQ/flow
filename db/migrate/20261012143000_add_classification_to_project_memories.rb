# frozen_string_literal: true

class AddClassificationToProjectMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :project_memories, :language, :string, null: false, default: "en"
    add_column :project_memories, :tags, :jsonb, null: false, default: []
  end
end
