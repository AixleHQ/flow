# frozen_string_literal: true

class CreateSessionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :session_logs do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false
      t.text :file_data
      t.bigint :file_size
      t.string :content_type
      t.timestamps
    end
  end
end
