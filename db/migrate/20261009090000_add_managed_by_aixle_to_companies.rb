# frozen_string_literal: true

class AddManagedByAixleToCompanies < ActiveRecord::Migration[8.1]
  def up
    add_column :companies, :managed_by_aixle, :boolean, default: false, null: false

    # Where we host, a company already running with nobody paying for it — ours,
    # and anything made from the admin before this flag existed — is one we
    # carry. Leaving it unflagged would put a billing tab in front of its admins
    # for a subscription that does not exist. Elsewhere nobody is billed, and
    # flagging would only take the session limit away from the company's admins.
    return unless Deployment.saas?

    execute(<<~SQL.squish)
      UPDATE companies SET managed_by_aixle = TRUE
      WHERE billing_state = 'active' AND stripe_customer_id IS NULL
    SQL
  end

  def down
    remove_column :companies, :managed_by_aixle
  end
end
