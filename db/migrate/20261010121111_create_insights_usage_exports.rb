# frozen_string_literal: true

class CreateInsightsUsageExports < ActiveRecord::Migration[8.1]
  def change
    # One row per terminal session we attempt to export to Aixle Insights,
    # claimed before the push and settled after it. Insights attributes an event
    # only within 7 days of its timestamp, so a push that fails has to be
    # replayable within that window rather than lost — and abandoned past it.
    create_table :insights_usage_exports do |t|
      t.references :terminal_session, null: false,
                   foreign_key: { on_delete: :cascade }, index: { unique: true }
      # Denormalized from the session so the ledger stays queryable per company
      # even while diagnosing why a company's events are not arriving (decision
      # [3]=b). nullify (not cascade) — a company is a far heavier object than a
      # session, and losing the audit row with it is not wanted; the session FK
      # already cascades the row away on the common path.
      t.references :company, null: true, foreign_key: { on_delete: :nullify }
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :records_sent, null: false, default: 0
      t.text :error
      t.datetime :exported_at
      t.timestamps

      t.index [ :state, :created_at ]
    end
  end
end
