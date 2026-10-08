# frozen_string_literal: true

require "test_helper"

class AnalyticsPeriodTest < ActiveSupport::TestCase
  test "a preset covers its days up to now" do
    travel_to Time.zone.parse("2026-10-08 12:00") do
      window = AnalyticsPeriod.window("7d")

      assert_equal "7d", window.key
      assert_equal 7.days.ago, window.from
      assert_equal Time.current, window.to
      assert_equal "day", window.bucket
    end
  end

  test "an unknown or missing period is the default preset" do
    assert_equal AnalyticsPeriod::DEFAULT, AnalyticsPeriod.window("2w").key
    assert_equal AnalyticsPeriod::DEFAULT, AnalyticsPeriod.window(nil).key
  end

  test "a custom range covers both of its days whole" do
    travel_to Time.zone.parse("2026-10-08 12:00") do
      window = AnalyticsPeriod.window("custom", from: "2026-09-24", to: "2026-10-07")

      assert_equal "custom", window.key
      assert_equal Time.zone.parse("2026-09-24 00:00"), window.from
      assert_equal Time.zone.parse("2026-10-07").end_of_day, window.to
      assert_equal 14, window.days
    end
  end

  test "a custom range ending in the future ends today" do
    travel_to Time.zone.parse("2026-10-08 12:00") do
      window = AnalyticsPeriod.window("custom", from: "2026-10-01", to: "2026-12-31")

      assert_equal Time.zone.parse("2026-10-08").end_of_day, window.to
    end
  end

  test "an unreadable custom range falls back to the default preset" do
    assert_equal AnalyticsPeriod::DEFAULT, AnalyticsPeriod.window("custom", from: "2026-10-08", to: "2026-09-24").key
    assert_equal AnalyticsPeriod::DEFAULT, AnalyticsPeriod.window("custom", from: "last week", to: "2026-09-24").key
    assert_equal AnalyticsPeriod::DEFAULT, AnalyticsPeriod.window("custom").key
  end

  test "a custom range buckets like the preset of about its length" do
    travel_to Time.zone.parse("2026-10-08 12:00") do
      assert_equal "day", AnalyticsPeriod.window("custom", from: "2026-09-24", to: "2026-10-08").bucket
      assert_equal "week", AnalyticsPeriod.window("custom", from: "2026-06-01", to: "2026-10-08").bucket
      assert_equal "month", AnalyticsPeriod.window("custom", from: "2025-10-01", to: "2026-10-08").bucket
    end
  end

  test "a resolved window passes through unchanged" do
    window = AnalyticsPeriod.window("90d")

    assert_same window, AnalyticsPeriod.window(window)
  end
end
