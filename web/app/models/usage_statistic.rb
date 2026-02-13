# frozen_string_literal: true

class UsageStatistic < ApplicationRecord
  belongs_to :terminal_session

  validates :tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
