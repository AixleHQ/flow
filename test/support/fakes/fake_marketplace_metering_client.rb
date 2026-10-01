# frozen_string_literal: true

# Canonical fake for Billing::MarketplaceMeteringClient. Never stub
# ::Aws::MarketplaceMetering directly (docs/testing.md §4, R2/R3): this
# application talks to AWS Marketplace through one adapter, and the tests below
# it drive this.
#
#   client = FakeMarketplaceMeteringClient.new
#   client.meter_usage(...)              # => a record id, recorded in #records
#   client.meter_usage(same hour)        # => :duplicate, as AWS answers
#
# Kept interface-identical by
# test/services/billing/marketplace_metering_client_contract_test.rb.
class FakeMarketplaceMeteringClient
  Record = Struct.new(:dimension, :quantity, :occurred_at, :allocations, keyword_init: true)

  attr_reader :records
  attr_accessor :configured, :failure

  def initialize(configured: true)
    @configured = configured
    @records = []
  end

  def configured?
    @configured
  end

  # One record per hour, as AWS counts them: a second for an hour already sent
  # answers :duplicate rather than raising, because the record exists.
  def meter_usage(dimension:, quantity:, occurred_at:, allocations: {})
    raise_failure!
    return :duplicate if records.any? { |r| r.occurred_at == occurred_at }

    records << Record.new(
      dimension: dimension, quantity: quantity, occurred_at: occurred_at, allocations: allocations
    )
    "record-#{records.size}"
  end

  def last_record
    records.last
  end

  private

  def raise_failure!
    return if failure.blank?

    raise Billing::MarketplaceMeteringClient::Error, failure
  end
end
