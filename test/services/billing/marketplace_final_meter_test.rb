# frozen_string_literal: true

require "test_helper"

# The hour AWS gives after a licence is deprovisioned, and what gets sent into
# it. The schedule cannot do this: it reports a closed hour at five past the
# next one, which for most deprovisioning times is already too late.
class Billing::MarketplaceFinalMeterTest < ActiveSupport::TestCase
  setup do
    @client = FakeMarketplaceSellerClient.new
    @meter = Billing::MarketplaceFinalMeter.new(client: @client)
    @company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    @license = create(:marketplace_license, :active, company: @company)
  end

  def change(max_sessions, at)
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: max_sessions, occurred_at: at)
  end

  # The whole point: the minutes since the hour began have not closed and so
  # belong to no scheduled run, yet they are inside the window AWS just opened.
  test "it sends the hour that has not closed yet" do
    change(2, Time.utc(2026, 10, 23, 8))

    travel_to Time.utc(2026, 10, 23, 10, 20) do
      @meter.call(@license)
    end

    partial = @client.recorded.find { |usage| usage.occurred_at == Time.utc(2026, 10, 23, 10) }
    assert_equal 40, partial.quantity, "two queues for twenty minutes is forty worker-minutes"
    assert_equal Billing::Meter::AwsMarketplaceSaas::DIMENSION, partial.dimension
    assert_equal @license.license_arn, partial.license_arn
  end

  # A licence deprovisioned at 10:02 is ahead of the 10:05 schedule, so the
  # closed hour has not been sent either. Sending it twice is answered
  # DuplicateRecord; sending it never cannot be recovered.
  test "it also sends the hour before, which the schedule may not have reached" do
    change(1, Time.utc(2026, 10, 23, 8))

    travel_to Time.utc(2026, 10, 23, 10, 2) do
      @meter.call(@license)
    end

    assert_equal [ Time.utc(2026, 10, 23, 9), Time.utc(2026, 10, 23, 10) ],
                 @client.recorded.map(&:occurred_at).sort
  end

  test "an hour with nothing in it is not sent" do
    travel_to Time.utc(2026, 10, 23, 10, 20) { @meter.call(@license) }

    assert_empty @client.recorded
  end

  # Under a minute rounds to nothing rather than to a billed minute.
  test "a part of a minute is not billed as one" do
    change(1, Time.utc(2026, 10, 23, 9, 59, 30))

    travel_to Time.utc(2026, 10, 23, 10, 0, 20) do
      @meter.call(@license)
    end

    assert_empty @client.recorded.select { |usage| usage.occurred_at == Time.utc(2026, 10, 23, 10) }
  end

  test "a licence AWS no longer accepts usage for is not metered" do
    @license.finish!
    change(5, Time.utc(2026, 10, 23, 8))

    travel_to(Time.utc(2026, 10, 23, 10, 20)) { @meter.call(@license) }

    assert_empty @client.recorded
  end

  test "an installation that sells nothing meters nothing" do
    @client.configured = false

    assert_empty @meter.call(@license)
  end

  # The caller's next step is to end the licence. A refusal that propagated
  # would leave it open, and the schedule would go on billing an entitlement
  # AWS has already revoked.
  test "a refusal is swallowed so the licence can still be ended" do
    change(1, Time.utc(2026, 10, 23, 8))
    @client.failure = Billing::MarketplaceSellerClient::Error.new("AWS said no")

    travel_to Time.utc(2026, 10, 23, 10, 20) do
      assert_empty @meter.call(@license)
    end
  end
end
