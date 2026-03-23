# frozen_string_literal: true

class FixAssetsUniqueIndexForSoftDelete < ActiveRecord::Migration[8.0]
  def change
    remove_index :assets, name: "index_assets_on_scope_folder_name"
    add_index :assets,
              "scope_type, scope_id, COALESCE(folder, ''::character varying), name",
              name: "index_assets_on_scope_folder_name",
              unique: true,
              where: "deleted_at IS NULL"
  end
end
