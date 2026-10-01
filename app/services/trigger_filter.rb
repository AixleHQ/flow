# frozen_string_literal: true

# Evaluates a TriggerBinding's filter_predicate against an event's data payload.
#
# A predicate is a JSONB hash keyed by a (dot-pathed) field. Each value is either:
#   • a scalar            → equality match (back-compat): {"channel" => "C1"}
#   • an operator object  → {"op" => "contains", "value" => "ship"}
#
# All conditions are AND-ed. An empty predicate matches any event.
# Field names may be dot-paths into nested data, e.g. "repository.name", "ref".
# Fields named in `ignore_case` compare without regard to case, regex included.
class TriggerFilter
  OPERATORS = %w[eq ne contains not_contains starts_with ends_with gt gte lt lte present blank in includes regex].freeze

  def self.match?(predicate, data, ignore_case: [])
    new(predicate, data, ignore_case: ignore_case).match?
  end

  def initialize(predicate, data, ignore_case: [])
    @predicate = predicate || {}
    @data = data || {}
    @ignore_case = Array(ignore_case).map(&:to_s)
  end

  def match?
    @predicate.all? do |field, spec|
      fold = @ignore_case.include?(field.to_s)
      actual = dig_path(field)
      if spec.is_a?(Hash) && spec.key?("op")
        evaluate(spec["op"].to_s, actual, spec["value"], fold)
      else
        fold_case(actual, fold) == fold_case(spec, fold)
      end
    end
  end

  private

  def dig_path(field)
    keys = field.to_s.split(".")
    keys.reduce(@data) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
  end

  def fold_case(value, fold)
    return value unless fold

    case value
    when String then value.downcase
    when Array then value.map { |v| fold_case(v, true) }
    else value
    end
  end

  def evaluate(op, actual, expected, fold)
    # A regex folds through its flag: downcasing the pattern would turn \D into \d.
    return safe_regex(expected, fold) { |re| actual.to_s.match?(re) } if op == "regex"

    actual = fold_case(actual, fold)
    expected = fold_case(expected, fold)
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
    # Array membership: `contains` compares strings, so "ai" would match "main".
    when "includes"     then actual.is_a?(Array) && actual.map(&:to_s).include?(expected.to_s)
    else false
    end
  end

  def numeric?(*values)
    values.all? { |v| v.to_s.match?(/\A-?\d+(\.\d+)?\z/) }
  end

  def safe_regex(pattern, ignore_case)
    yield Regexp.new(pattern.to_s, ignore_case ? Regexp::IGNORECASE : 0)
  rescue RegexpError
    false
  end
end
