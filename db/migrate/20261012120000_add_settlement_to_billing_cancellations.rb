# frozen_string_literal: true

class AddSettlementToBillingCancellations < ActiveRecord::Migration[8.1]
  def change
    change_table :billing_cancellations, bulk: true do |t|
      t.string :settlement_state
      t.jsonb :final_usage, default: {}, null: false
      t.string :final_invoice_id
      t.string :final_invoice_url
      t.datetime :settled_at
      t.text :settlement_error
    end
  end
end
