# frozen_string_literal: true

# TTL + reconciliation state for CI gates.
#
# A gate used to be resolvable by exactly one thing: the matching CI webhook. If
# that webhook never arrived — dropped delivery, a run that was deleted, a
# repository that is no longer linked to the project — the gate stayed `pending`
# forever and the column auto-trigger never fired again for that task.
#
# These columns give a gate a deadline (`expires_at`), record what the periodic
# reconciliation sweep saw (`last_reconciled_at`, `reconcile_attempts`,
# `reconciliation_log`) and carry the operator-facing explanation when a gate is
# marked stale (`diagnostic_reason`).
#
# Existing pending gates are backfilled to `created_at + TTL` so the first sweep
# treats them exactly like a gate created after this migration; already resolved
# gates get a deadline too, purely so the column is uniform (nothing reads it for
# a resolved gate).
class AddCiReconciliationToGates < ActiveRecord::Migration[8.1]
  # Mirrors the `gates.ttl_hours` default in config/settings.yml. Inlined rather
  # than read from Settings so a later settings change cannot rewrite history.
  BACKFILL_TTL = "12 hours"

  def up
    add_column :gates, :expires_at, :datetime
    add_column :gates, :last_reconciled_at, :datetime
    add_column :gates, :reconcile_attempts, :integer, default: 0, null: false
    add_column :gates, :diagnostic_reason, :string
    add_column :gates, :reconciliation_log, :jsonb, default: [], null: false

    say_with_time "Backfilling gates.expires_at from created_at" do
      execute(<<~SQL.squish)
        UPDATE gates
        SET expires_at = created_at + INTERVAL '#{BACKFILL_TTL}'
        WHERE expires_at IS NULL
      SQL
    end

    change_column_null :gates, :expires_at, false

    # The reconciliation sweep claims unresolved gates in creation order; the
    # partial index keeps it off the resolved rows, which are the bulk of the
    # table over time.
    add_index :gates, %i[status expires_at], where: "status <> 'resolved'",
                                            name: "index_gates_on_status_and_expires_at"
  end

  def down
    remove_index :gates, name: "index_gates_on_status_and_expires_at"
    remove_column :gates, :reconciliation_log
    remove_column :gates, :diagnostic_reason
    remove_column :gates, :reconcile_attempts
    remove_column :gates, :last_reconciled_at
    remove_column :gates, :expires_at
  end
end
