# frozen_string_literal: true

require "test_helper"

# The backfill in 20261027080000, which recovers what it can from the summary
# line of events written before `metered_receipts` existed.
#
# Exercised against the SQL the migration runs rather than by replaying the
# migration: the rule is the regular expression, and it is the rule that has to
# keep holding.
class MarketplaceSubscriptionEventReceiptsTest < ActiveSupport::TestCase
  PATTERN = <<~SQL.squish
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

  def event(metered, id: SecureRandom.uuid)
    MarketplaceSubscriptionEvent.create!(
      event_id: id, detail_type: "Purchase Agreement Ended",
      occurred_at: Time.current, metered: metered
    )
  end

  test "one receipt at the end of the line is recovered with its minutes" do
    e = event("sent=1:already=0:minutes=13:receipt=b7d9edab")

    ActiveRecord::Base.connection.execute(PATTERN)

    assert_equal({ "b7d9edab" => 13 }, e.reload.metered_receipts)
  end

  # `minutes=` is the total across the records one call sent, and nothing in the
  # line says which hour each receipt bought. Splitting it would be a guess.
  test "two receipts are left alone, because the line cannot say which bought what" do
    e = event("sent=2:already=0:minutes=72:receipt=af6cef33,bf6cef33")

    ActiveRecord::Base.connection.execute(PATTERN)

    assert_empty e.reload.metered_receipts
  end

  # There `minutes=` covers a record AWS did not honour, so it is not what the
  # receipt bought either.
  test "a line that ends in a refusal is left alone" do
    e = event("sent=1:already=0:minutes=5:receipt=cc11:refused=CustomerNotSubscribed")

    ActiveRecord::Base.connection.execute(PATTERN)

    assert_empty e.reload.metered_receipts
  end

  test "an event that sent nothing is left alone" do
    e = event("nothing to send")

    ActiveRecord::Base.connection.execute(PATTERN)

    assert_empty e.reload.metered_receipts
  end

  # The backfill is for rows written before the column; one the application has
  # already filled is not touched.
  test "a map the application wrote is not overwritten" do
    e = event("sent=1:already=0:minutes=13:receipt=b7d9edab")
    e.update!(metered_receipts: { "b7d9edab" => 11 })

    ActiveRecord::Base.connection.execute(PATTERN)

    assert_equal({ "b7d9edab" => 11 }, e.reload.metered_receipts)
  end
end
