# frozen_string_literal: true

class CreateCapacityMeteringTables < ActiveRecord::Migration[8.1]
  def change
    # An append-only log of what each company's limit became, and when. The
    # metered quantity is time-weighted, so the hour has to be reconstructed from
    # the changes rather than sampled — a sample cannot tell twenty minutes at
    # thirty from a whole hour at thirty.
    create_table :company_capacity_changes do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      # Null is the limit being removed: unbounded, and unbillable.
      t.integer :max_sessions
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false

      t.index [ :company_id, :occurred_at ]
      t.index :occurred_at
    end

    # One row per hour per provider, claimed before the call and settled after
    # it. AWS Marketplace rejects a record more than six hours after the event,
    # so a send that fails has to be replayable rather than lost.
    create_table :capacity_meter_reports do |t|
      t.string :provider, null: false
      t.datetime :period_start, null: false
      # The integral of available capacity over the hour, in queue-SECONDS.
      #
      # Seconds because they are exact: every change lands on a whole second, so
      # the integral is a whole number and nothing is rounded on the way in.
      # Queue-minutes is what anyone reads and what a provider is sent, derived
      # from this — and a provider that cannot take a fraction rounds at its own
      # edge rather than making every other provider inherit the loss.
      t.integer :quantity_seconds, null: false
      # The most offered at any instant. Not billed — it is what an operator
      # reads to size the cluster, and what makes a bill explicable.
      t.integer :peak_concurrent, null: false, default: 0
      t.integer :unbounded_companies, null: false, default: 0
      t.jsonb :breakdown, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.string :external_id
      t.text :error
      t.integer :attempts, null: false, default: 0
      t.datetime :reported_at
      t.timestamps

      t.index [ :provider, :period_start ], unique: true
      t.index [ :state, :period_start ]
    end
  end
end
