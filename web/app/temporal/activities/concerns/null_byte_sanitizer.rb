# frozen_string_literal: true

module Activities::Concerns::NullByteSanitizer
  extend ActiveSupport::Concern

  private

  def sanitize_null_bytes(obj)
    case obj
    when Hash
      obj.transform_values { |v| sanitize_null_bytes(v) }
    when Array
      obj.map { |v| sanitize_null_bytes(v) }
    when String
      obj.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\u0000")
    else
      obj
    end
  end
end
