# frozen_string_literal: true

require "test_helper"

# The adapter and its fake have to stay the same shape, or every test below the
# fake is testing something the application does not do.
class Billing::MarketplaceMeteringClientContractTest < ActiveSupport::TestCase
  METHODS = %i[configured? meter_usage].freeze

  test "the fake answers every method the adapter does, with the same arguments" do
    METHODS.each do |name|
      real = Billing::MarketplaceMeteringClient.instance_method(name)
      fake = FakeMarketplaceMeteringClient.instance_method(name)

      assert_equal real.parameters.map { |kind, key| [ kind, key ] }, fake.parameters.map { |kind, key| [ kind, key ] },
                   "#{name} differs between Billing::MarketplaceMeteringClient and its fake"
    end
  end

  # An installation that was not bought through Marketplace has no product code,
  # and must not call out at all: there is nothing to bill against and the call
  # would be refused anyway.
  test "an installation with no product code refuses rather than dialling out" do
    Settings.stubs(:aws_marketplace).returns(Hashie::Mash.new(product_code: nil))
    client = Billing::MarketplaceMeteringClient.new

    assert_not client.configured?
    error = assert_raises(Billing::MarketplaceMeteringClient::Error) do
      client.meter_usage(dimension: "queue_minute", quantity: 60, occurred_at: Time.current)
    end
    assert_match(/product code/, error.message)
  end
end
