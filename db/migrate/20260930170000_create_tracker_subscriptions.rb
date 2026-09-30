# frozen_string_literal: true

class CreateTrackerSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # How a tracker's events reach /webhooks/trackers: one per connection and
    # external project, or one per connection (external_scope_id NULL) for a
    # provider whose webhook covers the whole site.
    create_table :tracker_subscriptions do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :external_scope_id
      t.string :strategy, null: false
      t.string :endpoint_token, null: false
      t.text :encrypted_secret
      t.string :provider_subscription_id
      t.jsonb :settings, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at
      t.datetime :last_event_at
      t.string :last_error
      t.timestamps
    end
    add_index :tracker_subscriptions, :endpoint_token, unique: true
    add_index :tracker_subscriptions, %i[integration_id external_scope_id], unique: true, nulls_not_distinct: true,
      name: "idx_tracker_subscriptions_scope"
    add_index :tracker_subscriptions, :expires_at
    add_index :tracker_subscriptions, :provider_subscription_id

    create_table :tracker_deliveries do |t|
      t.references :tracker_subscription, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :dedup_key, null: false
      t.jsonb :notifications, null: false, default: []
      t.string :status, null: false, default: "received"
      t.jsonb :detail, null: false, default: {}
      t.timestamps
    end
    add_index :tracker_deliveries, %i[tracker_subscription_id dedup_key], unique: true, name: "idx_tracker_deliveries_dedup"
    add_index :tracker_deliveries, :created_at
  end
end
