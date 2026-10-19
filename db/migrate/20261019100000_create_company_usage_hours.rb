# frozen_string_literal: true

# What each company used, hour by hour, for the platform tenant report
# (docs/design/tenant-usage-report.md §4). Written for every company, the
# unlimited and the managed ones included; days, weeks and months are sums.
class CreateCompanyUsageHours < ActiveRecord::Migration[8.1]
  def change
    create_table :company_usage_hours do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :period_start, null: false
      # Null when the company had no limit at any moment of the hour.
      t.integer :limit_min
      t.integer :limit_max
      t.integer :unlimited_seconds, null: false, default: 0
      # Copied from company_capacity_usages: what the meter billed, never recomputed.
      t.integer :offered_seconds, null: false, default: 0
      t.string :billing_class, null: false
      t.integer :occupied_seconds, null: false, default: 0
      t.integer :peak_workers, null: false, default: 0
      t.integer :sessions_queued, null: false, default: 0
      t.integer :sessions_admitted, null: false, default: 0
      t.integer :wait_seconds_total, null: false, default: 0
      t.integer :wait_seconds_max, null: false, default: 0
      t.integer :sessions_succeeded, null: false, default: 0
      t.integer :sessions_failed, null: false, default: 0
      t.datetime :computed_at, null: false

      t.index %i[company_id period_start], unique: true
      t.index :period_start
    end
  end
end
