# frozen_string_literal: true

# The order a session/run list was asked for, in ransack's `q[s]` form
# ("cost_cents desc"). The column comes from each model's ransack setup, so a run
# sorts by its step sessions' summed cost and a session by its own.
#
# Applied here instead of by ransack's own sorting for two reasons: a row with no
# value (no duration yet) has to sink to the bottom in both directions, and the
# project feed sorts a UNION of two tables by one column.
class SessionListSort
  FIELDS = %w[created_at cost_cents total_tokens duration_seconds].freeze
  DEFAULT_FIELD = "created_at"

  attr_reader :field, :direction

  def initialize(param)
    field, direction = param.to_s.split(/\s+/, 2)
    if FIELDS.include?(field)
      @field = field
      @direction = direction.to_s.downcase == "asc" ? "asc" : "desc"
    else
      @field = DEFAULT_FIELD
      @direction = "desc"
    end
  end

  def to_s
    "#{field} #{direction}"
  end

  # The sort column as an Arel node over `model`'s table.
  def column(model)
    model.ransack(s: to_s).sorts.first.attr
  end

  def order(node)
    node.public_send(direction).nulls_last
  end
end
