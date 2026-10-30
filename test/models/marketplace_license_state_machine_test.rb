# frozen_string_literal: true

require "test_helper"

# What the machine is for is the refusals. SQS neither orders messages nor
# delivers them once, so every one of these is a message that will arrive.
class MarketplaceLicenseStateMachineTest < ActiveSupport::TestCase
  test "a new licence starts pending" do
    assert MarketplaceLicense.new.pending?
  end

  test "the three moves AWS can make" do
    license = create(:marketplace_license)

    assert license.confirm!
    assert license.active?

    assert license.close!
    assert license.ending?

    assert license.finish!
    assert license.ended?
  end

  # Both columns existed from the first migration and nothing wrote either, so
  # a licence carried a subscription date of nil for its whole life and an end
  # date of nil after it ended.
  test "the dates are stamped as the licence moves" do
    license = create(:marketplace_license)

    travel_to(Time.utc(2026, 10, 24, 4, 24)) { license.confirm! }
    assert_equal Time.utc(2026, 10, 24, 4, 24), license.reload.subscribed_at
    assert_nil license.ended_at

    travel_to(Time.utc(2026, 10, 24, 5, 12)) { license.finish! }
    assert_equal Time.utc(2026, 10, 24, 5, 12), license.reload.ended_at
  end

  # `confirm` accepts its own result so a redelivery is a no-op, and a no-op
  # must not move the date a bill may later be read against.
  test "a redelivered confirmation does not move the subscription date" do
    license = create(:marketplace_license)
    travel_to(Time.utc(2026, 10, 24, 4, 24)) { license.confirm! }

    travel_to(Time.utc(2026, 10, 24, 6)) { license.confirm! }

    assert_equal Time.utc(2026, 10, 24, 4, 24), license.reload.subscribed_at
  end

  # The close can arrive before the creation ever did, and the licence then goes
  # straight to ended without a confirmation to stamp a start.
  test "a licence that ends without ever being confirmed still records its end" do
    license = create(:marketplace_license)

    travel_to(Time.utc(2026, 10, 24, 5, 12)) { license.finish! }

    assert_nil license.reload.subscribed_at
    assert_equal Time.utc(2026, 10, 24, 5, 12), license.ended_at
  end

  # The one that costs money: a licence AWS has deprovisioned must not be
  # revived by a creation message that overtook the deprovisioning, because
  # `active` is what makes the next hour billable.
  test "a stale confirmation cannot revive an ended licence" do
    license = create(:marketplace_license, :ended)

    assert_not license.may_confirm?
    assert_raises(AASM::InvalidTransition) { license.confirm! }
    assert license.reload.ended?
  end

  test "nothing leaves ended" do
    license = create(:marketplace_license, :ended)

    assert_equal [], license.available_events(:subscription_state)
  end

  # A closing agreement is equally not reopened: the hour after it closed is
  # the one the final meter is about to report, and `active` would let the
  # schedule report it a second time.
  test "a stale confirmation cannot reopen a closing licence" do
    license = create(:marketplace_license, :active)
    license.close!

    assert_not license.may_confirm?
    assert license.ending?
  end

  # Redelivery is normal, not an error: SQS promises at-least-once.
  test "a repeated confirmation is a no-op" do
    license = create(:marketplace_license)
    license.confirm!

    assert license.confirm!
    assert license.active?
  end

  test "a repeated close is a no-op" do
    license = create(:marketplace_license, :active)
    license.close!

    assert license.close!
    assert license.ending?
  end

  # `finish` is the exception, because the final meter runs beside it and must
  # not run twice. The caller checks rather than the machine allowing it.
  test "finishing twice is refused rather than silently repeated" do
    license = create(:marketplace_license, :active)
    license.finish!

    assert_not license.may_finish?
  end

  # Out of order: the close can arrive before the creation ever did.
  test "a close before any confirmation still closes" do
    license = create(:marketplace_license)

    assert license.close!
    assert license.ending?
  end

  test "a deprovisioning before any confirmation still ends" do
    license = create(:marketplace_license)

    assert license.finish!
    assert license.ended?
  end

  # The states the meter reads, driven through the machine rather than set.
  test "metering follows the state the machine put the licence in" do
    license = create(:marketplace_license, company: create(:company))

    assert_not license.meterable?, "pending is before AWS accepts anything"

    license.confirm!
    assert license.meterable?

    license.close!
    assert license.meterable?, "the final hour is reported from ending"

    license.finish!
    assert_not license.meterable?
  end
end
