# frozen_string_literal: true

# Inbound webhook idempotency store. The unique (webhook_endpoint_id,
# idempotency_key) index makes at-least-once delivery safe: a redelivered
# webhook (same provider delivery id / Slack event_id) is accepted with 2xx but
# only processed once.
class CreateReceivedWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :received_webhooks do |t|
      t.references :webhook_endpoint, null: false, foreign_key: { on_delete: :cascade }
      t.string :idempotency_key, null: false
      t.string :event_type
      t.string :status, null: false, default: "received"
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :received_webhooks, %i[webhook_endpoint_id idempotency_key], unique: true,
      name: "index_received_webhooks_on_endpoint_and_idempotency_key"
  end
end
