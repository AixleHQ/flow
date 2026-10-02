# frozen_string_literal: true

require "test_helper"

class Billing::Meter::AwsMarketplaceTest < ActiveSupport::TestCase
  setup do
    @client = FakeMarketplaceMeteringClient.new
    @adapter = Billing::Meter::AwsMarketplace.new(client: @client)
    @hour = Time.utc(2026, 9, 30, 10)
    @acme = create(:company)
    @globex = create(:company)
  end

  def report(breakdown)
    CapacityMeterReport.create!(
      provider: "aws_marketplace", period_start: @hour,
      quantity_seconds: breakdown.values.sum, breakdown: breakdown, state: "pending"
    )
  end

  # One agreement, one record: the installation total goes as a single call, and
  # the companies inside it travel as allocations rather than as separate bills.
  test "the installation's hour is sent as one record" do
    result = @adapter.deliver(report(@acme.id.to_s => 5400, @globex.id.to_s => 1800))

    assert_equal 1, @client.records.size
    record = @client.last_record
    assert_equal "queue_minute", record.dimension
    assert_equal 120, record.quantity, "7200 queue-seconds is 120 queue-minutes"
    assert_equal @hour, record.occurred_at
    assert_equal "record-1", result
  end

  # The dimension is the one field publication makes permanent, and it has to
  # match the listing character for character.
  test "the dimension is the identifier the listing was published with" do
    assert_equal "queue_minute", Billing::Meter::AwsMarketplace::DIMENSION
  end

  # AWS takes an integer. Rounding down gives the minute away rather than
  # charging for one that was not offered.
  test "a fractional minute is given away rather than charged" do
    @adapter.deliver(report(@acme.id.to_s => 119))

    assert_equal 1, @client.last_record.quantity, "119 seconds is 1.98 minutes, sent as 1"
  end

  # AWS refuses the whole call if the parts do not add up, so the split has to
  # absorb its own rounding.
  test "allocations add up to the quantity that was sent" do
    @adapter.deliver(report(@acme.id.to_s => 110, @globex.id.to_s => 110))

    record = @client.last_record
    assert_equal record.quantity, record.allocations.values.sum
  end

  test "an hour with no capacity carries no allocations" do
    @adapter.deliver(report(@acme.id.to_s => 0))

    assert_equal 0, @client.last_record.quantity
    assert_empty @client.last_record.allocations
  end

  # A second call for an hour AWS already holds is not a failure: the record
  # exists. Raising instead would replay the hour until the window closed.
  test "an hour AWS already holds settles rather than fails" do
    rows = { @acme.id.to_s => 5400 }
    @adapter.deliver(report(rows))
    CapacityMeterReport.delete_all

    result = @adapter.deliver(report(rows))

    assert_equal 1, @client.records.size
    assert_equal "aws:already-recorded:2026-09-30T10:00:00Z", result
  end

  # A raise is what puts the hour back in the replay window, so a refusal must
  # not be swallowed.
  test "a refusal is raised rather than reported as sent" do
    @client.failure = "CustomerNotEntitledException: no subscription"

    assert_raises(Billing::MarketplaceMeteringClient::Error) do
      @adapter.deliver(report(@acme.id.to_s => 60))
    end
  end
end
