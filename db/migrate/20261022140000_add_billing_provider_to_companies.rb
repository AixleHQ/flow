# frozen_string_literal: true

# Names who invoices a company's capacity, so that one installation can hold
# more than one answer. Nothing reads the column for a decision yet.
class AddBillingProviderToCompanies < ActiveRecord::Migration[8.1]
  def up
    add_column :companies, :billing_provider, :string, null: false, default: "none"
    add_index :companies, :billing_provider

    # A company we carry pays nobody, whatever Stripe still remembers about it.
    # One can hold a subscription from before we took it on — that is what
    # Company#start_billing_company_we_stop_carrying reads when it stops being
    # carried — so backfilling from the customer id alone would mark it as
    # paying, and the first thing to consult this column would start billing it.
    execute(<<~SQL.squish)
      UPDATE companies
         SET billing_provider = 'stripe'
       WHERE stripe_customer_id IS NOT NULL
         AND managed_by_aixle = false
    SQL
  end

  def down
    remove_column :companies, :billing_provider
  end
end
