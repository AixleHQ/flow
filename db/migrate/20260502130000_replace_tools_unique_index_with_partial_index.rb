# frozen_string_literal: true

class ReplaceToolsUniqueIndexWithPartialIndex < ActiveRecord::Migration[7.2]
  def change
    remove_index :tools, %i[scope_type scope_id name], name: "index_tools_on_scope_type_and_scope_id_and_name"
    add_index :tools, %i[scope_type scope_id name],
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_tools_on_scope_type_and_scope_id_and_name"
  end
end
