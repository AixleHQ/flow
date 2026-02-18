# frozen_string_literal: true

class UpdateAssetsUniqueIndexWithFolder < ActiveRecord::Migration[8.1]
  def change
    remove_index :assets, %i[scope_type scope_id name]
    add_index :assets, "scope_type, scope_id, COALESCE(folder, ''), name",
              unique: true, name: "index_assets_on_scope_folder_name"
  end
end
