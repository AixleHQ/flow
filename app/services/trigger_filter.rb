# frozen_string_literal: true

# Evaluates a TriggerBinding's filter_predicate against an event's data payload.
#
# A predicate is a JSONB hash keyed by a (dot-pathed) field. Each value is either:
#   • a scalar            → equality match (back-compat): {"channel" => "C1"}
#   • an operator object  → {"op" => "contains", "value" => "ship"}
#
# All conditions are AND-ed. An empty predicate matches any event.
# Field names may be dot-paths into nested data, e.g. "repository.name", "ref".
class TriggerFilter
  OPERATORS = %w[eq ne contains not_contains starts_with ends_with gt gte lt lte present blank in regex].freeze

  def self.match?(predicate, data)
    new(predicate, data).match?
  end

  def initialize(predicate, data)
    @predicate = predicate || {}
    @data = data || {}
  end

  def match?
    @predicate.all? do |field, spec|
      actual = dig_path(field)
      if spec.is_a?(Hash) && spec.key?("op")
        evaluate(spec["op"].to_s, actual, spec["value"])
      else
        actual == spec
      end
    end
  end

  private

  def dig_path(field)
    keys = field.to_s.split(".")
    keys.reduce(@data) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
  end

  def evaluate(op, actual, expected)
    case op
    when "eq"           then actual == expected
    when "ne"           then actual != expected
    when "contains"     then actual.to_s.include?(expected.to_s)
    when "not_contains" then !actual.to_s.include?(expected.to_s)
    when "starts_with"  then actual.to_s.start_with?(expected.to_s)
    when "ends_with"    then actual.to_s.end_with?(expected.to_s)
    when "gt"           then numeric?(actual, expected) && actual.to_f > expected.to_f
    when "gte"          then numeric?(actual, expected) && actual.to_f >= expected.to_f
    when "lt"           then numeric?(actual, expected) && actual.to_f < expected.to_f
    when "lte"          then numeric?(actual, expected) && actual.to_f <= expected.to_f
    when "present"      then actual.present?
    when "blank"        then actual.blank?
    when "in"           then Array(expected).map(&:to_s).include?(actual.to_s)
    when "regex"        then safe_regex(expected) { |re| actual.to_s.match?(re) }
    else false
    end
  end

  def numeric?(*values)
    values.all? { |v| v.to_s.match?(/\A-?\d+(\.\d+)?\z/) }
  end

  def safe_regex(pattern)
    yield Regexp.new(pattern.to_s)
  rescue RegexpError
    false
  end
end
