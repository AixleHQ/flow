# frozen_string_literal: true

class UsageStatistic < ApplicationRecord
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
