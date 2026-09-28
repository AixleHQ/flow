# frozen_string_literal: true

# What one company was offered during one hour, in queue-seconds.
#
# Ours, not a provider's. capacity_meter_reports exist to be sent somewhere and
# carry the per-company split as a jsonb blob inside an installation-wide row;
# these exist to be read — by the free allowance, by an invoice conversation, and
# by anyone asking what a company actually had.
#
# Written for every active company, including the ones nobody is billed for. What
# is invoiced is a narrower question, and the meter report answers it.
class CompanyCapacityUsage < ApplicationRecord
  belongs_to :company

  validates :period_start, presence: true, uniqueness: { scope: :company_id }
  validates :quantity_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :since, ->(time) { where(period_start: time...) }

  def self.total_seconds_for(company_id)
    where(company_id: company_id).sum(:quantity_seconds)
  end

  # One statement, so an hour that is measured twice keeps the first answer
  # rather than raising — the meter claims its report row the same way.
  def self.record!(company_id:, period_start:, quantity_seconds:)
    upsert(
      { company_id: company_id, period_start: period_start,
        quantity_seconds: quantity_seconds, created_at: Time.current },
      unique_by: %i[company_id period_start]
    )
  end

  def quantity_minutes = (BigDecimal(quantity_seconds) / 60).round(4)
end
