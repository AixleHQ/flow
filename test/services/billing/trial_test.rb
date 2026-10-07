# frozen_string_literal: true

require "test_helper"

class Billing::TrialTest < ActiveSupport::TestCase
  setup do
    saas!
    @company = create(:company, :trialing)
  end

  def saas!(mode = Deployment::SAAS)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def used!(hours, at: Time.utc(2026, 9, 29, 10))
    CompanyCapacityUsage.record!(
      company_id: @company.id, period_start: at, quantity_seconds: (hours * 3600).to_i
    )
  end

  test "it reads the allowance from the settings" do
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 250))

    assert_equal 250, Billing::Trial.queue_hours
    assert_equal 900_000, Billing::Trial.seconds
  end

  test "a fresh company has the whole allowance" do
    assert_equal Billing::Trial.seconds, Billing::Trial.remaining_seconds(@company)
    assert_not Billing::Trial.exhausted?(@company)
  end

  # The spend is a sum over the usage log rather than a counter beside it, so
  # there is nothing that can drift from what was actually offered.
  test "what it has spent is the sum of the hours it was offered" do
    used!(30, at: Time.utc(2026, 9, 29, 10))
    used!(20, at: Time.utc(2026, 9, 29, 11))

    assert_equal 50 * 3600, Billing::Trial.used_seconds(@company)
    assert_in_delta 50.0, Billing::Trial.remaining_hours(@company)
  end

  test "spending the allowance exactly is spending it" do
    used!(Billing::Trial.queue_hours)

    assert Billing::Trial.exhausted?(@company)
    assert_equal 0, Billing::Trial.remaining_seconds(@company)
  end

  test "remaining never goes below nothing" do
    used!(Billing::Trial.queue_hours + 40)

    assert_equal 0, Billing::Trial.remaining_seconds(@company)
  end

  test "enforce stops a company that has spent it" do
    used!(Billing::Trial.queue_hours)

    assert_equal [ @company.id ], Billing::Trial.enforce!

    assert @company.reload.billing_blocked?
    assert_equal "allowance", @company.billing_status
  end

  test "enforce leaves a company that has not" do
    used!(10)

    assert_empty Billing::Trial.enforce!
    assert @company.reload.billing_trialing?
  end

  # A company someone is paying for has no allowance to spend, whatever its usage
  # says.
  test "enforce leaves a paying company alone" do
    paying = create(:company)
    CompanyCapacityUsage.record!(
      company_id: paying.id, period_start: Time.utc(2026, 9, 29, 10),
      quantity_seconds: Billing::Trial.seconds * 10
    )

    assert_empty Billing::Trial.enforce!
    assert paying.reload.billing_active?
  end

  # A self-hosted operator pays nobody and a Marketplace customer bought their
  # capacity from AWS, so neither has an allowance to run out of.
  test "nothing is enforced outside the hosted product" do
    used!(Billing::Trial.queue_hours)
    saas!(Deployment::SELF_HOSTED)

    assert_empty Billing::Trial.enforce!
    assert @company.reload.billing_trialing?
  end

  test "only a company that has spent the allowance is stopped" do
    assert_equal 0, Billing::Trial.ceiling_for("blocked")
    assert_nil Billing::Trial.ceiling_for("trialing")
    assert_nil Billing::Trial.ceiling_for("active")
  end

  # What is left is a quantity; what an admin wants to know is how long it lasts
  # at the rate they are running.
  test "it says how long what is left lasts at the current rate" do
    used!(60)

    assert_in_delta 40.0, Billing::Trial.hours_left_at(@company, 1)
    assert_in_delta 4.0, Billing::Trial.hours_left_at(@company, 10)
  end

  test "there is no rate to divide by when no limit is set" do
    assert_nil Billing::Trial.hours_left_at(@company, nil)
    assert_nil Billing::Trial.hours_left_at(@company, 0)
  end

  test "applies only where we host" do
    assert Billing::Trial.applies?(@company)

    saas!(Deployment::AWS_MARKETPLACE)
    assert_not Billing::Trial.applies?(@company)
  end
end
