# frozen_string_literal: true

module Trackers
  # Serialization shared by the tracker value objects, so nested ones (a status
  # inside an issue) come out as plain JSON.
  module Value
    def as_json(*)
      to_h.transform_keys(&:to_s).transform_values { |v| v.respond_to?(:as_json) ? v.as_json : v }
    end
  end
end
