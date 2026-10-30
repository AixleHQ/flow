# frozen_string_literal: true

# What a company's billing state was, and from when.
#
# The twin of CompanyCapacityChange, and for the same reason: an hour is
# measured after it closes, so reading the company as it is at that moment
# bills the whole hour at whatever it has become. A workspace stopped for most
# of an hour and started at :47 was offered nothing for the first forty-seven
# minutes, and this is what says so.
class CompanyBillingStateChange < ApplicationRecord
  belongs_to :company

  validates :billing_state, inclusion: { in: Company::BILLING_STATES }
  validates :occurred_at, presence: true

  scope :until, ->(time) { where(occurred_at: ...time) }
  scope :during, ->(range) { where(occurred_at: range) }

  # What each company's billing state was immediately before `time`. A company
  # with no entry is absent, which the caller resolves from the live row rather
  # than guessing -- the same contract CompanyCapacityChange has.
  def self.state_at(time)
    where(id: select("DISTINCT ON (company_id) id")
            .until(time)
            .order(:company_id, occurred_at: :desc, id: :desc))
      .pluck(:company_id, :billing_state)
      .to_h
  end

  def self.record!(company_id:, billing_state:, occurred_at: Time.current)
    create!(company_id: company_id, billing_state: billing_state, occurred_at: occurred_at)
  end

  # Brings the log back to what the row says, for every company the two
  # disagree on. The log is written by Company's callback and by nothing else,
  # so a write that went round it -- a pod on the previous release during a
  # deploy, a console -- leaves the hour measured against a state the
  # workspace has already left, until the next change happens to be logged.
  # Dated now rather than then, because when the row changed is exactly what
  # nobody knows. Answers how many were brought back.
  def self.reconcile!(now: Time.current)
    latest = where(id: select("DISTINCT ON (company_id) id").order(:company_id, occurred_at: :desc, id: :desc))
                 .select(:company_id, :billing_state)
    drifted = Company
                .joins("LEFT JOIN (#{latest.to_sql}) latest ON latest.company_id = companies.id")
                .where("latest.company_id IS NULL OR latest.billing_state <> companies.billing_state")
                .pluck(:id, :billing_state)

    drifted.each { |company_id, state| record!(company_id: company_id, billing_state: state, occurred_at: now) }
    drifted.size
  end
end
