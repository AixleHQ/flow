# frozen_string_literal: true

class AddMeteredReceiptsToMarketplaceSubscriptionEvents < ActiveRecord::Migration[8.1]
  # AWS's receipt for each record the final meter sent, and the minutes it
  # bought. The hourly meter keeps the same evidence on its ledger row; this
  # path writes no ledger row, so without this the minutes it sends -- the last
  # part-hour of a cancelling customer, which is the whole reason it exists --
  # are recorded nowhere a figure can be built from, and the Billing tab
  # understated what AWS had been told.
  #
  # Keyed by receipt because the two cancellation events send the same record
  # and AWS answers both with the id it issued first: counted by id, the repeat
  # counts once.
  def change
    add_column :marketplace_subscription_events, :metered_receipts, :jsonb, default: {}, null: false
  end
end
