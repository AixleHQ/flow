# frozen_string_literal: true

# The run relay's claim: stamped in the same transaction that selects the rows
# FOR UPDATE SKIP LOCKED, so a claimed run stays invisible to other drainers for
# a grace window after the locks are gone (GateReconciler's pattern).
class AddRelayClaimedAtToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_runs, :relay_claimed_at, :datetime
  end
end
