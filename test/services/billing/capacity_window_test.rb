# frozen_string_literal: true

require "test_helper"

class Billing::CapacityWindowTest < ActiveSupport::TestCase
  setup do
    @hour = Time.utc(2026, 9, 23, 10)
    @acme = create(:company)
    @globex = create(:company)
  end

  def change(company, max_sessions, at)
    CompanyCapacityChange.record!(company_id: company.id, max_sessions: max_sessions, occurred_at: at)
  end

  def window = Billing::CapacityWindow.for_hour(@hour)

  # A whole hour at N is N queue-hours, i.e. N * 60 queue-minutes.
  def assert_minutes(expected, result, message = nil)
    assert_equal BigDecimal(expected.to_s), result.quantity_minutes, message
  end

  test "an hour with no capacity anywhere measures nothing" do
    result = window

    assert_minutes 0, result
    assert_empty result.per_company
    assert_equal 2, result.unbounded_companies
  end

  test "a limit unchanged through the hour is measured once" do
    change(@acme, 10, @hour - 2.hours)

    result = window

    assert_minutes 600, result, "ten queues for a whole hour is 600 queue-minutes"
    assert_equal 10, result.peak_concurrent
  end

  test "companies are summed" do
    change(@acme, 10, @hour - 2.hours)
    change(@globex, 5, @hour - 2.hours)

    assert_minutes 900, window
  end

  # The point of the log: a sample taken at any single moment misses this.
  test "a limit raised for part of the hour is billed for exactly that part" do
    change(@acme, 2, @hour - 2.hours)
    change(@acme, 50, @hour + 20.minutes)
    change(@acme, 2, @hour + 30.minutes)

    result = window

    # 20 min at 2, 10 min at 50, 30 min at 2 = 40 + 500 + 60
    assert_minutes 600, result
    assert_equal 50, result.peak_concurrent, "the peak is measured, and not what is billed"
  end

  # The canonical question: half an hour at one, half at three. Two queue-hours,
  # because that is what the customer was given — not three, which is only the
  # most they ever had at once.
  test "half an hour at one and half at three is two queue-hours" do
    change(@acme, 1, @hour - 2.hours)
    change(@acme, 3, @hour + 30.minutes)

    result = window

    assert_minutes 120, result
    assert_equal 3, result.peak_concurrent
  end

  test "the same hour the other way round costs the same" do
    change(@acme, 3, @hour - 2.hours)
    change(@acme, 1, @hour + 30.minutes)

    assert_minutes 120, window
  end

  # Peak of the sum, not sum of the peaks: the installation never offered more
  # than ten at any instant, so ten is what it is billed.
  test "capacity moving between companies is not double counted" do
    change(@acme, 10, @hour - 2.hours)
    change(@acme, nil, @hour + 30.minutes)
    change(@globex, 10, @hour + 30.minutes)

    assert_minutes 600, window, "ten throughout, whoever was holding it"
    assert_equal 10, window.peak_concurrent
  end

  test "a limit removed mid-hour still bills the hour at its peak" do
    change(@acme, 8, @hour - 2.hours)
    change(@acme, nil, @hour + 45.minutes)

    result = window

    assert_minutes 360, result, "45 minutes at eight, then nothing"
    assert_equal 2, result.unbounded_companies, "both the company that lost its limit and the one that never had one"
  end

  test "changes after the hour do not reach it" do
    change(@acme, 3, @hour - 2.hours)
    change(@acme, 99, @hour + 1.hour + 1.minute)

    assert_minutes 180, window
  end

  # Capacity set before the log existed has no entry to read, so the live row is
  # the only truth available for it.
  test "a company with no log entry falls back to its live limit" do
    SessionConcurrencyLimit.set!(scope: @acme, max_sessions: 7)
    CompanyCapacityChange.delete_all

    assert_minutes 420, window
  end

  # How an internal organisation is free today: it has no limit row at all, so it
  # is unbounded AND contributes nothing to the metered quantity. The two facts
  # are the same absence, which is what makes the arrangement fragile — a paying
  # customer whose row is deleted becomes free by the same mechanism.
  test "a company with no limit is unbounded and adds nothing to the bill" do
    change(@acme, 10, @hour - 2.hours)

    result = window

    assert_minutes 600, result, "only the bounded company is billed"
    assert_equal [ @acme.id ], result.per_company.keys, "the unbounded company is not in the breakdown at all"
    assert_equal 1, result.unbounded_companies
  end

  # Admission refuses a suspended company (SessionService#preflight_company_active!),
  # so its capacity cannot be occupied and billing for it would overcharge. The two
  # rules have to agree: were admission to let it run, skipping it here would make
  # suspending a company a way to keep the capacity and stop paying for it.
  test "a suspended company is not metered, because it cannot run sessions" do
    change(@acme, 10, @hour - 2.hours)
    change(@globex, 5, @hour - 2.hours)
    @globex.update_column(:state, "suspended")

    result = window

    assert_minutes 600, result
    assert_equal [ @acme.id ], result.per_company.keys
  end

  test "an archived company is not metered on the same rule" do
    change(@acme, 10, @hour - 2.hours)
    change(@globex, 5, @hour - 2.hours)
    @globex.update_column(:state, "archived")

    assert_minutes 600, window
  end
end
