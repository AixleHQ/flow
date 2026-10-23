# frozen_string_literal: true

class CreateMarketplaceSubscriptionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_subscription_events do |t|
      # The EventBridge envelope's own id. Unique because SQS delivers at least
      # once and a message that arrives twice is one event, not two.
      t.string :event_id, null: false
      t.string :detail_type, null: false

      # Agreement events carry no licence ARN and licence events carry no
      # subscription identifier of their own, so both keys are kept and either
      # may be the one that matches.
      t.string :agreement_id
      t.string :license_arn

      t.references :marketplace_license, foreign_key: true, index: true

      # When AWS says it happened, not when we read it: the queue's order is not
      # the events' order, and an event applied out of order is the failure this
      # table exists to make visible.
      t.datetime :occurred_at, null: false
      t.datetime :applied_at
      t.jsonb :detail, null: false, default: {}
      t.string :failure

      t.timestamps
    end

    add_index :marketplace_subscription_events, :event_id, unique: true
    # The sweep's query: everything still unapplied, oldest first.
    add_index :marketplace_subscription_events, %i[applied_at occurred_at]
    add_index :marketplace_subscription_events, :agreement_id

    # Agreement events can only be matched by this, and until now nothing read
    # it. Not unique: a renewal creates a new agreement for the same customer
    # and an amendment can leave two rows pointing at one.
    add_index :marketplace_licenses, :agreement_id
  end
end
