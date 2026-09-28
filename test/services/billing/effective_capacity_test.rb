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

  # The free allowance is a quantity, not a smaller workspace: a company on it
  # runs what its admin chose and simply spends the hours faster.
  test "a trialing company runs the limit it asked for" do
    company = create(:company, :trialing)
    limit!(company, 12)

    assert_equal 12, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "an unbounded trialing company is bounded by nothing either" do
    company = create(:company, :trialing)

    assert_not_includes Billing::EffectiveCapacity.for_companies, company.id
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
