# frozen_string_literal: true

# A soft-deleted workflow's triggers were left switched on, so its schedules,
# webhooks and Slack bindings kept starting runs. Deleting a workflow now turns
# them off; this does the same for the ones deleted before. Their Temporal
# schedules are removed by the next ScheduleReconciler.reconcile_all (worker boot).
class DisableTriggersOfDeletedWorkflows < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE trigger_bindings SET enabled = FALSE, updated_at = NOW()
       WHERE enabled = TRUE
         AND workflow_id IN (SELECT id FROM workflows WHERE deleted_at IS NOT NULL)
    SQL
  end

  def down
    # Not reversible: which of them were on is not recorded.
  end
end
