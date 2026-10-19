# frozen_string_literal: true

module Usage
  # The tenant report's data: one row per company per UTC day, summed from
  # company_usage_hours. The page sums days into weeks, months and custom ranges
  # itself, and compares each with the period before.
  class TenantReport
    # What one page load carries: a little over a year of days.
    HISTORY = 400.days

    DAY = Arel.sql("(date_trunc('day', period_start))::date")

    # Each column with how a day combines its hours. The billing class of a day
    # is the one its last measured hour had.
    AGGREGATES = {
      hours: "COUNT(*)",
      offered_seconds: "SUM(offered_seconds)",
      occupied_seconds: "SUM(occupied_seconds)",
      unlimited_seconds: "SUM(unlimited_seconds)",
      limit_min: "MIN(limit_min)",
      limit_max: "MAX(limit_max)",
      peak_workers: "MAX(peak_workers)",
      sessions_queued: "SUM(sessions_queued)",
      sessions_admitted: "SUM(sessions_admitted)",
      wait_seconds_total: "SUM(wait_seconds_total)",
      wait_seconds_max: "MAX(wait_seconds_max)",
      sessions_succeeded: "SUM(sessions_succeeded)",
      sessions_failed: "SUM(sessions_failed)",
      billing_class: "(ARRAY_AGG(billing_class ORDER BY period_start DESC))[1]"
    }.freeze

    def initialize(now: Time.current)
      @since = (now.utc - HISTORY).beginning_of_day
    end

    def to_h
      days = daily_rows
      {
        tenants: tenants(days.pluck(:company_id).uniq),
        days: days,
        measured_through: CompanyUsageHour.maximum(:period_start)&.then { |last| (last + 1.hour).utc.iso8601 }
      }
    end

    private

    def daily_rows
      CompanyUsageHour.where(period_start: @since..)
                      .group(:company_id, DAY)
                      .order(DAY, :company_id)
                      .pluck(:company_id, DAY, *AGGREGATES.values.map { |sql| Arel.sql(sql) })
                      .map do |company_id, day, *values|
                        { company_id: company_id, day: day.iso8601, **AGGREGATES.keys.zip(values).to_h }
                      end
    end

    def tenants(company_ids)
      Company.where(id: company_ids).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    end
  end
end
