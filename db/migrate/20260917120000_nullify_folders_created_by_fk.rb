# frozen_string_literal: true

# `folders` landed with a NOT NULL `created_by_id` behind an ON DELETE RESTRICT
# foreign key, which is the one shape permanent (hard) user deletion cannot
# survive: EnablePermanentUserDeletion flipped every other authorship FK to
# ON DELETE :nullify precisely so Postgres anonymises the row instead of
# refusing the DELETE. A folder must outlive the user who created it the same
# way an asset does, so give it the same treatment.
class NullifyFoldersCreatedByFk < ActiveRecord::Migration[8.1]
  def up
    change_column_null :folders, :created_by_id, true
    remove_foreign_key :folders, column: :created_by_id
    add_foreign_key :folders, :users, column: :created_by_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :folders, column: :created_by_id
    add_foreign_key :folders, :users, column: :created_by_id
    change_column_null :folders, :created_by_id, false
  end
end
