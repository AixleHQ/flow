# frozen_string_literal: true

# Audit + idempotency ledger for the trigger layer. One row per (event, matched
# trigger). The unique dedup_key prevents an at-least-once event (e.g. a
# redelivered webhook) from launching the same workflow twice — the principled
# replacement for relying on the Redis cooldown for correctness. It also answers
# "which event, matched by which binding, started this run".
class CreateTriggerDispatches < ActiveRecord::Migration[8.1]
  def change
    create_table :trigger_dispatches do |t|
      t.references :trigger_event, null: false, foreign_key: { on_delete: :cascade }
      t.references :trigger_binding, foreign_key: { on_delete: :nullify }
      t.references :workflow_run, foreign_key: { on_delete: :nullify }

      t.string :source
      t.string :status, null: false, default: "matched"
      t.string :dedup_key, null: false
      t.jsonb :detail, null: false, default: {}

      t.timestamps
    end

    add_index :trigger_dispatches, :dedup_key, unique: true
  end
end
