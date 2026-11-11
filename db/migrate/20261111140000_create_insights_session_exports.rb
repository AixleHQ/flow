# frozen_string_literal: true

# The outbox of the Insights export (docs/design/insights-usage-export.md §6): one row per
# session to deliver, written when the session's records are materialized.
class CreateInsightsSessionExports < ActiveRecord::Migration[8.1]
  def change
    create_table :insights_session_exports do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :integration, foreign_key: { on_delete: :nullify }
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :claimed_until
      t.string :last_error
      t.integer :record_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.datetime :delivered_at
      t.timestamps

      t.index %i[state next_attempt_at]
    end
  end
end
