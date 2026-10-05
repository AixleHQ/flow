# frozen_string_literal: true

require_relative "20260930130000_add_number_to_board_tasks"

# The trigger covered pods still on the previous release, which inserted tasks
# with no number. Every process now sets it, so a missing number is a bug and
# NOT NULL is what should reject it.
class DropBoardTaskNumberTrigger < ActiveRecord::Migration[8.1]
  def up
    numbering_migration.drop_number_trigger
  end

  def down
    numbering_migration.create_number_trigger
  end

  private

  # Same verbosity as this migration, so `suppress_messages` covers the SQL too.
  def numbering_migration
    AddNumberToBoardTasks.new.tap { |migration| migration.verbose = verbose }
  end
end
