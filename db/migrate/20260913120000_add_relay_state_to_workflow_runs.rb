# frozen_string_literal: true

# Brings run dispatch into the transactional outbox that trigger events already
# use. `state` is the run's own lifecycle; these columns record whether the
# Temporal execution that drives it was ever confirmed started.
#
# Default "dispatched", not "pending", for the same reason trigger_events does
# it: every existing row, and any future creation path that does not opt in, must
# not be swept by the relay. WorkflowService.start writes "pending" explicitly.
class AddRelayStateToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_runs, :relay_state, :string, default: "dispatched", null: false
    add_column :workflow_runs, :relay_attempts, :integer, default: 0, null: false
    add_column :workflow_runs, :relay_error, :string

    add_index :workflow_runs, [ :relay_state, :created_at ],
      name: "index_workflow_runs_pending_relay",
      where: "(relay_state)::text = 'pending'::text"
  end
end
