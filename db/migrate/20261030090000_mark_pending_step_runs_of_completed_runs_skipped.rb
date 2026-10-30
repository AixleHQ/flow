# frozen_string_literal: true

# A step its skip policy skipped kept its step run `pending` for good, even after
# its run completed (fixed by the `mark-policy-skipped-step-runs` patch in
# WorkflowExecutionWorkflow). A completed run leaves no other step run pending, so
# every one left is such a step. Failed and cancelled runs already moved theirs to
# failed or cancelled, and cannot tell a skipped step from one never reached.
#
# Idempotent: a marked step run is no longer pending.
class MarkPendingStepRunsOfCompletedRunsSkipped < ActiveRecord::Migration[8.1]
  REASON = "All required outputs already exist from previous steps"

  def up
    result = execute(<<~SQL.squish)
      UPDATE step_runs
      SET state = 'skipped',
          skip_reason = #{connection.quote(REASON)},
          completed_at = COALESCE(workflow_runs.completed_at, workflow_runs.updated_at),
          updated_at = NOW()
      FROM workflow_runs
      WHERE step_runs.workflow_run_id = workflow_runs.id
        AND workflow_runs.state = 'completed'
        AND step_runs.state = 'pending'
    SQL
    say "Marked #{result.cmd_tuples} step runs skipped"
  end

  # Not reversible: a step that never ran is not waiting to.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
