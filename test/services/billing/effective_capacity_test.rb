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

  # A company given more before a trial could not be is still held to one: the
  # stored number is what it runs once it pays.
  test "a trialing company runs one worker, whatever limit it has" do
    company = create(:company)
    limit!(company, 12)
    company.update_column(:billing_state, "trialing")

    assert_equal 1, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "an unbounded trialing company runs one worker too" do
    company = create(:company)
    company.update_column(:billing_state, "trialing")

    assert_equal 1, Billing::EffectiveCapacity.for_companies[company.id]
  end

  test "a blocked company runs nothing" do
    company = create(:company, billing_state: "blocked", billing_block_reason: "canceled")
    limit!(company, 12)

    assert_equal 0, Billing::EffectiveCapacity.for_companies[company.id]
  end

  # Nobody is on an allowance outside the hosted product, so nothing is capped
  # there however the column happens to read.
  test "nothing is capped outside the hosted product" do
    company = create(:company, :trialing)
    with_mode(Deployment::SELF_HOSTED)
    limit!(company, 12)

    assert_empty Billing::EffectiveCapacity.ceilings
    assert_equal 12, Billing::EffectiveCapacity.for_companies[company.id]
  end
end
