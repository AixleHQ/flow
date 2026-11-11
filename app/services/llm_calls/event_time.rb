# frozen_string_literal: true

module LlmCalls
  # A usage event's "timestamp": epoch milliseconds, or an ISO-8601 string where the
  # adapter took it off a log line. nil when it is neither.
  module EventTime
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}/

    module_function

    def parse(raw)
      return nil if raw.blank?
      return Time.zone.parse(raw) if raw.is_a?(String) && raw.match?(ISO_DATE)
      return nil unless raw.to_s.match?(/\A\d+(\.\d+)?\z/)

      Time.zone.at(raw.to_i / 1000.0)
    rescue ArgumentError
      nil
    end
  end
end
