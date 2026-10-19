# frozen_string_literal: true

class UsageStatistic < ApplicationRecord
  # Total tokens are the four breakdown columns summed. The aggregate `tokens`
  # column is legacy — nothing writes it any more — and is deliberately ignored.
  TOTAL_TOKENS_SUM_SQL = "COALESCE(SUM(" \
                         "usage_statistics.input_tokens + usage_statistics.output_tokens + " \
                         "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0)".freeze

  belongs_to :terminal_session

  validates :tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :input_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :output_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_write_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_read_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def total_tokens
    input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
  end
end
