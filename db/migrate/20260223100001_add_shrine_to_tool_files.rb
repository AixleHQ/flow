# frozen_string_literal: true

class AddShrineToToolFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_files, :file_data, :text
    change_column_null :tool_files, :content, true
  end
end
