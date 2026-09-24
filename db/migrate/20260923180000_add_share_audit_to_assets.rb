# frozen_string_literal: true

class AddShareAuditToAssets < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :assets, :shared_at, :datetime, if_not_exists: true
    add_reference :assets, :shared_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false,
                                       if_not_exists: true
    add_reference :assets, :shared_in_session, foreign_key: { to_table: :terminal_sessions, on_delete: :nullify },
                                               index: false, if_not_exists: true

    # The link of an asset deleted before this kept serving it.
    execute "UPDATE assets SET public = false, public_token = NULL WHERE deleted_at IS NOT NULL AND public_token IS NOT NULL"

    add_index :assets, :public_token, unique: true, where: "public_token IS NOT NULL",
                                      algorithm: :concurrently, if_not_exists: true
    add_index :assets, :shared_by_id, where: "shared_by_id IS NOT NULL", algorithm: :concurrently, if_not_exists: true
    add_index :assets, :shared_in_session_id, where: "shared_in_session_id IS NOT NULL",
                                              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :assets, :shared_in_session_id, algorithm: :concurrently, if_exists: true
    remove_index :assets, :shared_by_id, algorithm: :concurrently, if_exists: true
    remove_index :assets, :public_token, algorithm: :concurrently, if_exists: true
    remove_reference :assets, :shared_in_session, foreign_key: { to_table: :terminal_sessions }, if_exists: true
    remove_reference :assets, :shared_by, foreign_key: { to_table: :users }, if_exists: true
    remove_column :assets, :shared_at, if_exists: true
  end
end
