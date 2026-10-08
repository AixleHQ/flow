# frozen_string_literal: true

# The periods every analytics view offers and how a time series buckets each one,
# defined once for every analytics service.
module AnalyticsPeriod
  DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  DEFAULT = "30d"
  CUSTOM = "custom"
  BUCKETS = { "7d" => "day", "30d" => "day", "90d" => "week", "1y" => "month" }.freeze

  # The sessions that do work, and so count toward usage and session totals: a
  # login (auth_setup) or a tool setup is neither.
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  # A resolved period: the preset it came from ("custom" for a picked range)
  # and the span of time it covers, both ends inclusive.
  Window = Data.define(:key, :range) do
    def from = range.begin
    def to = range.end

    def days
      (to.to_date - from.to_date).to_i + 1
    end

    # A custom range buckets like the preset of about its length, so a picked
    # fortnight reads day by day and a picked half-year week by week.
    def bucket
      BUCKETS.fetch(key) do
        if days <= 31 then "day"
        elsif days <= 180 then "week"
        else "month"
        end
      end
    end
  end

  module_function

  # The window a request asked for: a preset key, or "custom" with ISO dates.
  # Anything unreadable — an unknown key, a malformed date, an end before its
  # start — falls back to the default preset rather than failing the page.
  def window(period, from: nil, to: nil)
    return period if period.is_a?(Window)

    (period.to_s == CUSTOM && custom_window(from, to)) || preset_window(period)
  end

  # DATE_TRUNC('<the period's bucket>', <attribute>) as an Arel node, for
  # group/order/pluck — built, not interpolated.
  def date_trunc(period, attribute)
    Arel::Nodes::NamedFunction.new("DATE_TRUNC", [ Arel::Nodes.build_quoted(window(period).bucket), attribute ])
  end

  def preset_window(period)
    key = DAYS.key?(period.to_s) ? period.to_s : DEFAULT
    Window.new(key: key, range: DAYS.fetch(key).days.ago..Time.current)
  end

  def custom_window(from, to)
    from_date = Date.iso8601(from.to_s)
    to_date = [ Date.iso8601(to.to_s), Time.current.to_date ].min
    return if from_date > to_date

    Window.new(key: CUSTOM, range: from_date.in_time_zone.beginning_of_day..to_date.in_time_zone.end_of_day)
  rescue Date::Error
    nil
  end
  private_class_method :preset_window, :custom_window
end
