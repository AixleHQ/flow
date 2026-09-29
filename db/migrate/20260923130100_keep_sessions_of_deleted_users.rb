# frozen_string_literal: true

# A terminal session is the company's record of work done and money spent — its
# analytics are built on sessions and their usage rows. Permanently deleting a
# user destroyed every one of theirs, so the company's history shrank with each
# deletion. They now stay, attributed to nobody ("Deleted user"), like every
# other authorship row since EnablePermanentUserDeletion.
class KeepSessionsOfDeletedUsers < ActiveRecord::Migration[8.1]
  def up
    change_column_null :terminal_sessions, :user_id, true
    remove_foreign_key :terminal_sessions, :users
    add_foreign_key :terminal_sessions, :users, on_delete: :nullify
  end

  def down
    remove_foreign_key :terminal_sessions, :users
    add_foreign_key :terminal_sessions, :users
    change_column_null :terminal_sessions, :user_id, false
  end
end
