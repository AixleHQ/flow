# frozen_string_literal: true

module Activities
  module Usage
    # Measures closed hours into company_usage_hours: the ones not yet measured
    # when the schedule runs it, or the range it is given.
    class RollupHoursActivity < ::Activities::Base
      def run(input = nil)
        ::Usage::HourlyRollup.call(from: parse(input&.from_hour), to: parse(input&.to_hour))
      end

      private

      def parse(value)
        Time.iso8601(value) if value.present?
      end
    end
  end
end
