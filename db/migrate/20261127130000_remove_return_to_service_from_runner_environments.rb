# frozen_string_literal: true

# Return to service is gone (docs/design/agent-runtimes/DESIGN.md §5.2): `failed` is final,
# so the `resetting` state and the failure streak go with it. A machine that is `resetting`
# when this runs becomes `failed`, with a reason that says its reset was cancelled; it is
# revoked and registered again like any other failed machine.
class RemoveReturnToServiceFromRunnerEnvironments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE runner_environments
      SET state = 'failed',
          current_session_id = NULL,
          state_reason = 'its reset was cancelled: Return to service was removed. Revoke the machine and add it again.',
          updated_at = NOW()
      WHERE state = 'resetting'
    SQL
    remove_column :runner_environments, :consecutive_failures
  end

  def down
    add_column :runner_environments, :consecutive_failures, :integer, default: 0, null: false
  end
end
