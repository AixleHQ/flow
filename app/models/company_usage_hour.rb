# frozen_string_literal: true

# What one company used during one closed UTC hour: the capacity it was billed
# for, the workers it actually held, how long its sessions queued and how they
# ended. Written by Usage::HourlyRollup for every company, billed or not, and
# read by the platform tenant report.
#
# Not the billing ledger. company_capacity_usages is what the meter sends a
# provider; offered_seconds here is a copy of it, so the report shows what was
# billed and a recompute can never change a billed number.
class CompanyUsageHour < ApplicationRecord
  # Why an hour is, or is not, billed. Checked in this order.
  #
  #   not_metered  self-hosted: nobody is billed
  #   inactive     the company is suspended or archived and runs nothing
  #   managed      carried by Aixle (managed_by_aixle)
  #   blocked      the free allowance is spent, or the subscription ended
  #   trial        spending the free allowance
  #   unlimited    no limit for the whole hour, so there is nothing to meter
  #   no_customer  billable, but no Stripe customer to send the minutes to
  #   paying       billed through Stripe or AWS Marketplace
  BILLING_CLASSES = %w[not_metered inactive managed blocked trial unlimited no_customer paying].freeze

  belongs_to :company

  validates :period_start, presence: true, uniqueness: { scope: :company_id }
  validates :billing_class, inclusion: { in: BILLING_CLASSES }
end
