# frozen_string_literal: true

# A list's date-range filter as two ransack scopes over created_at:
# `q[created_from]` and `q[created_until]` take calendar dates (YYYY-MM-DD) and
# include the whole of both days. An unreadable date filters nothing.
module CreatedWithinDates
  extend ActiveSupport::Concern

  included do
    scope :created_from, ->(date) { (day = parse_filter_date(date)) ? where(created_at: day.beginning_of_day..) : all }
    scope :created_until, ->(date) { (day = parse_filter_date(date)) ? where(created_at: ..day.end_of_day) : all }
  end

  class_methods do
    def parse_filter_date(value)
      Date.iso8601(value.to_s).in_time_zone
    rescue Date::Error
      nil
    end
  end
end
