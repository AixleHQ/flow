# frozen_string_literal: true

class AddStripeToCompanies < ActiveRecord::Migration[8.1]
  def change
    # Created lazily, when a card is first added — not at signup. Signing up
    # already waits on an email round trip, and a Stripe outage must not be able
    # to stop somebody registering.
    add_column :companies, :stripe_customer_id, :string
    add_column :companies, :stripe_subscription_id, :string

    add_index :companies, :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL"
  end
end
