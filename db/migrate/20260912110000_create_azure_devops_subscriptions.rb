# frozen_string_literal: true

# Azure DevOps Service Hooks, the parity extension (§11 of
# docs/design/azure-devops-integration.md).
#
# Two tables, and the second one is the point: Azure gives no delivery
# guarantees. A subscription that fails often enough goes on probation — during
# which new events are simply not sent — and can be disabled outright, and
# duplicate and out-of-order delivery are both normal. So an event is persisted
# and deduplicated BEFORE it is acknowledged, and everything downstream treats a
# payload as a notification to go and re-read authoritative state rather than as
# the state itself.
class CreateAzureDevopsSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :azure_devops_subscriptions do |t|
      t.references :integration, null: false, foreign_key: true

      # The public half of the receiving URL. It ROUTES a delivery to a
      # connection and is not a secret — the basic-auth password below is what
      # authenticates one. Keeping those separate is what lets the URL appear in
      # Azure's UI, its delivery history and its error mails.
      t.string :endpoint_id, null: false

      # Azure webhooks authenticate with HTTP basic auth; there is no HMAC
      # signature to verify, so copying GitHub's verification would silently
      # accept anything. Encrypted at rest and compared in constant time.
      t.text :encrypted_password, null: false

      # Azure's own subscription id, needed to update or delete it later. Null
      # until the subscription is actually created upstream.
      t.string :azure_subscription_id
      t.string :event_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :error_code
      t.datetime :last_event_at
      t.datetime :last_checked_at
      t.timestamps
    end

    add_index :azure_devops_subscriptions, :endpoint_id, unique: true
    add_index :azure_devops_subscriptions, %i[integration_id event_type],
              unique: true, name: "idx_ado_subscriptions_integration_event"

    # One row per delivery Azure says it made. The unique index is the whole
    # mechanism: a redelivery of an event already recorded is acknowledged and
    # dropped instead of resolving a gate twice.
    create_table :azure_devops_deliveries do |t|
      t.references :azure_devops_subscription, null: false, foreign_key: true,
                                               index: { name: "idx_ado_deliveries_subscription" }
      t.string :event_id, null: false
      t.string :event_type
      t.datetime :received_at, null: false
      t.timestamps
    end

    add_index :azure_devops_deliveries, %i[azure_devops_subscription_id event_id],
              unique: true, name: "idx_ado_deliveries_event"
    add_index :azure_devops_deliveries, :received_at, name: "idx_ado_deliveries_received_at"
  end
end
