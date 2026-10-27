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
  def up
    add_column :marketplace_subscription_events, :metered_receipts, :jsonb, default: {}, null: false

    backfill_from_the_summary_line
  end

  def down
    remove_column :marketplace_subscription_events, :metered_receipts
  end

  private

  # What can be recovered from rows written before the column existed.
  #
  # Only where the line carries exactly ONE receipt, because `minutes=` is the
  # total across the records a call sent while `receipt=` lists them: a call
  # that sent two hours states 72 minutes and two ids, and nothing in the line
  # says which hour was which. Those are left empty rather than split on a
  # guess — their quantities are in the seller account's CloudTrail if anyone
  # ever needs them exactly.
  #
  # The receipt must also be the LAST field, which skips a line ending
  # `:refused=…`: there `minutes=` covers a record AWS did not honour, so it is
  # not what the receipt bought either.
  def backfill_from_the_summary_line
    execute(<<~SQL.squish)
      UPDATE marketplace_subscription_events
         SET metered_receipts = jsonb_build_object(
               substring(metered FROM 'receipt=([^:,]+)$'),
               (substring(metered FROM 'minutes=([0-9]+)'))::int
             )
       WHERE metered IS NOT NULL
         AND metered ~ 'receipt=[^:,]+$'
         AND metered ~ 'minutes=[0-9]+'
         AND metered_receipts = '{}'::jsonb
    SQL
  end
end
