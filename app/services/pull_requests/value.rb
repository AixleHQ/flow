# frozen_string_literal: true

module PullRequests
  # JSON for the value objects, nested ones included, in the shape tools return.
  module Value
    def as_json(*)
      to_h.transform_keys(&:to_s).transform_values { |v| serialize(v) }
    end

    private

    def serialize(value)
      case value
      when Array then value.map { |v| serialize(v) }
      when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601
      else value.respond_to?(:as_json) ? value.as_json : value
      end
    end
  end
end
