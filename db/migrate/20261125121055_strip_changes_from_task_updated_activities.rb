# frozen_string_literal: true

# task_updated activities now record only who and when. Older rows carry the
# full old/new values in metadata.changes; the values are not recoverable
# after this runs, so there is no down.
class StripChangesFromTaskUpdatedActivities < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE board_activities SET metadata = metadata - 'changes'
      WHERE event_type = 'task_updated' AND metadata ? 'changes'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
