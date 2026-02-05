# frozen_string_literal: true

class DropSessionTools < ActiveRecord::Migration[8.0]
  def up
    drop_table :session_tools
  end

  def down
    create_table :session_tools do |t|
      t.references :terminal_session, null: false, foreign_key: true
      t.references :tool, null: false, foreign_key: true
      t.timestamps
    end

    add_index :session_tools, %i[terminal_session_id tool_id], unique: true
  end
end
