# frozen_string_literal: true

class UsageStatistic < ApplicationRecord
  # Match #total_tokens per session before summing: a group may mix detailed
  # usage with legacy rows that only have the aggregate tokens column.
  TOTAL_TOKENS_SUM_SQL = "COALESCE(SUM(COALESCE(NULLIF(" \
                         "usage_statistics.input_tokens + usage_statistics.output_tokens + " \
                         "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens, 0), " \
                         "usage_statistics.tokens)), 0)".freeze

  belongs_to :terminal_session

  validates :tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :input_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :output_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_write_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_read_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # Breakdown available → sum components; otherwise fall back to aggregate `tokens`
  def total_tokens
    breakdown = input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
    breakdown.positive? ? breakdown : tokens
  end
end
