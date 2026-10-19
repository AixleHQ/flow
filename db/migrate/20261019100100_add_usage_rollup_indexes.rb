# frozen_string_literal: true

# The hourly usage rollup reads admissions still held or released since the hour
# began, and sessions that ended in it. Neither column was indexed, so every run
# scanned both tables whole.
class AddUsageRollupIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :session_admissions, :released_at, algorithm: :concurrently, if_not_exists: true
    add_index :terminal_sessions, :finished_at, algorithm: :concurrently, if_not_exists: true
  end
end
