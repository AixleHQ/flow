# frozen_string_literal: true

require "test_helper"

class Billing::EffectiveCapacityTest < ActiveSupport::TestCase
  setup { with_mode(Deployment::SAAS) }

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def limit!(company, max_sessions)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: max_sessions)
  end

  test "a paying company gets the limit it set" do
    company = create(:company)
    limit!(company, 12)

    assert_equal 12, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "a company that set no limit is bounded by nothing" do
    company = create(:company)

    assert_not_includes Billing::EffectiveCapacity.for_companies, company.id
  end

  # The limit is what they asked for; the cap is what they get until someone
  # pays. Refusing the higher number outright would throw away the plan they
  # chose at signup.
  test "a trialing company is capped below the limit it asked for" do
    company = create(:company, :trialing)
    limit!(company, 12)

    assert_equal Billing::Trial::MAX_SESSIONS, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "a trialing company that asked for less keeps the smaller number" do
    company = create(:company, :trialing)
    limit!(company, 1)

    assert_equal 1, Billing::EffectiveCapacity.for_companies[company.id]
  end

  # "No limit set" is not a way past the cap.
  test "an unbounded trialing company is bounded by the cap" do
    company = create(:company, :trialing)

    assert_equal Billing::Trial::MAX_SESSIONS, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "a blocked company runs nothing" do
    company = create(:company, :billing_blocked)
    limit!(company, 12)

    assert_equal 0, Billing::EffectiveCapacity.for_companies[company.id]
  end

  # Nobody is on an allowance outside the hosted product, so nothing is capped
  # there however the column happens to read.
  test "nothing is capped outside the hosted product" do
    company = create(:company, :trialing)
    limit!(company, 12)
    with_mode(Deployment::SELF_HOSTED)

    assert_empty Billing::EffectiveCapacity.ceilings
    assert_equal 12, Billing::EffectiveCapacity.for_companies[company.id]
  end
end
