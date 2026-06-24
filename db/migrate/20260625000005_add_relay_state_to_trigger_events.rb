# frozen_string_literal: true

# Turns trigger_events into the transactional-outbox table. Internal producers
# record an event as "pending" inside the same transaction as their domain
# write; a relay (Temporal cron) sweeps any event left pending past a grace
# window (a crash victim) and dispatches it idempotently.
#
# The column DEFAULT is "dispatched" so existing rows — and any path that forgets
# to opt in — are inert (never re-fired). Only producers that explicitly pass
# relay_state: "pending" enrol in the relay.
class AddRelayStateToTriggerEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :trigger_events, :relay_state, :string, null: false, default: "dispatched"
    add_column :trigger_events, :dispatched_at, :datetime
    add_column :trigger_events, :relay_attempts, :integer, null: false, default: 0
    add_column :trigger_events, :relay_error, :string
    add_reference :trigger_events, :actor, foreign_key: { to_table: :users }, null: true

    # The relay sweep only ever scans not-yet-done rows; a partial index keeps it
    # cheap as the (mostly-dispatched) event log grows.
    add_index :trigger_events, [ :relay_state, :created_at ],
      where: "relay_state IN ('pending', 'dispatching')",
      name: "index_trigger_events_pending_relay"
  end
end
