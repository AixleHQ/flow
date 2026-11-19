# frozen_string_literal: true

# The outbox of the Insights relay (docs/design/insights-otlp-relay.md §5): one row per
# OTLP request an exported session's agent sent, already enriched and masked, gzipped.
# Delivered rows are deleted; a row Insights refused, or that failed for a week, stays as
# `failed` so the project's card can say why.
class CreateInsightsOtlpBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :insights_otlp_batches do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }
      t.string :signal, null: false
      t.binary :payload, null: false
      t.integer :record_count, null: false
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :claimed_until
      t.string :last_error
      t.timestamps

      t.index %i[integration_id state next_attempt_at], name: "index_insights_otlp_batches_due"
      t.index %i[project_id state]
    end
  end
end
