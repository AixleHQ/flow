# frozen_string_literal: true

class AddCapacityTrialBilling < ActiveRecord::Migration[8.1]
  def up
    # Our own record of what every company was offered, hour by hour. The meter
    # reports already hold this, but as a jsonb blob keyed by company inside an
    # installation-wide row — enough to send a provider, useless for answering
    # "how much has this company used", which is the question the free allowance
    # and every invoice conversation start from.
    #
    # It also means the allowance needs no counter of its own: what a company has
    # used is a sum over these rows, and a sum cannot drift from the thing it
    # sums.
    create_table :company_capacity_usages do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :period_start, null: false
      # Queue-SECONDS offered during the hour, on the same terms as
      # capacity_meter_reports.quantity_seconds: exact, never rounded here.
      t.integer :quantity_seconds, null: false, default: 0
      t.datetime :created_at, null: false

      t.index [ :company_id, :period_start ], unique: true
      t.index :period_start
    end

    add_column :companies, :billing_state, :string, null: false, default: "trialing"
    add_index :companies, :billing_state

    # Every company that already exists predates the free allowance and is not on
    # one: our own, every self-hosted installation's, and anything an operator
    # made from the admin. Only a company that signs itself up after this starts
    # out trialing.
    execute("UPDATE companies SET billing_state = 'active'")
  end

  def down
    remove_column :companies, :billing_state
    drop_table :company_capacity_usages
  end
end
