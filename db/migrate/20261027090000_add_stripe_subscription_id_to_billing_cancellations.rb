# frozen_string_literal: true

class AddStripeSubscriptionIdToBillingCancellations < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_cancellations, :stripe_subscription_id, :string
  end
end
