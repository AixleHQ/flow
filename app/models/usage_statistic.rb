# frozen_string_literal: true

class UsageStatistic < ApplicationRecord
  TOTAL_TOKENS_SUM_SQL = "COALESCE(SUM(" \
                         "usage_statistics.input_tokens + usage_statistics.output_tokens + " \
                         "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0)".freeze

  # The legacy aggregate column goes in a later migration. DB Migrate runs before
  # pods roll, so every pod still serving traffic must already ignore it — a pod
  # that knows the column includes it in every INSERT.
  self.ignored_columns += [ "tokens" ]

  belongs_to :terminal_session

  validates :cost_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :input_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :output_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_write_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cache_read_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def total_tokens
    input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
  end
end
