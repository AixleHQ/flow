# frozen_string_literal: true

require "test_helper"

class Activities::Usage::RollupHoursActivityTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  test "measures the range it is given" do
    from = Time.utc(2026, 10, 1, 0)

    result = run_activity(Activities::Usage::RollupHoursActivity,
                          { "from_hour" => from.iso8601, "to_hour" => (from + 2.hours).iso8601 })

    assert_equal from.iso8601, result[:from]
    assert_equal [ from, from + 1.hour ], CompanyUsageHour.where(company: @company).order(:period_start).pluck(:period_start)
  end

  test "measures the last closed hours when the schedule runs it with no range" do
    travel_to Time.utc(2026, 10, 14, 10, 10) do
      run_activity(Activities::Usage::RollupHoursActivity, {})
    end

    assert_equal Time.utc(2026, 10, 14, 9), CompanyUsageHour.where(company: @company).maximum(:period_start)
    assert_equal Usage::HourlyRollup::TRAILING_HOURS, CompanyUsageHour.where(company: @company).count
  end
end
