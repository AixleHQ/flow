# frozen_string_literal: true

class AddPublicSharingToRunAndTaskAssets < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[workflow_run_assets task_assets].freeze

  def up
    TABLES.each do |table|
      add_column table, :public_token, :string, if_not_exists: true
      add_column table, :shared_at, :datetime, if_not_exists: true
      add_reference table, :shared_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false,
                                       if_not_exists: true
      add_reference table, :shared_in_session, foreign_key: { to_table: :terminal_sessions, on_delete: :nullify },
                                               index: false, if_not_exists: true

      add_index table, :public_token, unique: true, where: "public_token IS NOT NULL",
                                      algorithm: :concurrently, if_not_exists: true
      add_index table, :shared_by_id, where: "shared_by_id IS NOT NULL", algorithm: :concurrently, if_not_exists: true
      add_index table, :shared_in_session_id, where: "shared_in_session_id IS NOT NULL",
                                              algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, :shared_in_session_id, algorithm: :concurrently, if_exists: true
      remove_index table, :shared_by_id, algorithm: :concurrently, if_exists: true
      remove_index table, :public_token, algorithm: :concurrently, if_exists: true
      remove_reference table, :shared_in_session, foreign_key: { to_table: :terminal_sessions }, if_exists: true
      remove_reference table, :shared_by, foreign_key: { to_table: :users }, if_exists: true
      remove_column table, :shared_at, if_exists: true
      remove_column table, :public_token, if_exists: true
    end
  end
end
