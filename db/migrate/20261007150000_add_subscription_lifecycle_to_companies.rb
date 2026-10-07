# frozen_string_literal: true

class AddSubscriptionLifecycleToCompanies < ActiveRecord::Migration[8.1]
  def change
    change_table :companies, bulk: true do |t|
      t.datetime :billing_period_starts_at
      t.datetime :billing_period_ends_at
      # Set while a cancellation is scheduled, and kept once it has happened, as
      # the date the subscription ended.
      t.datetime :billing_cancels_at
      t.string :billing_block_reason
      t.string :billing_unpaid_invoice_url
      # When the last Stripe event that changed this company was created. Stripe
      # does not deliver in order, so an older event arriving late is dropped.
      t.datetime :billing_event_at
    end

    # One row per cancellation rather than columns on the company: a company can
    # cancel, resume and cancel again, and every reason is worth keeping.
    create_table :billing_cancellations do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :reason
      t.text :comment
      t.datetime :cancels_at, null: false
      t.datetime :resumed_at
      t.timestamps
    end
  end
end
