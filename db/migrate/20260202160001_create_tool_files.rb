# frozen_string_literal: true

class CreateToolFiles < ActiveRecord::Migration[7.2]
  def change
    create_table :tool_files do |t|
      t.references :tool, null: false, foreign_key: true
      t.string :path, null: false           # full path in container, e.g. "/app/script.py"
      t.text :content, null: false          # file content
      t.timestamps
    end

    add_index :tool_files, %i[tool_id path], unique: true
  end
end
