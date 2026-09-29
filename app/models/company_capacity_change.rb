# frozen_string_literal: true

class CompanyCapacityChange < ApplicationRecord
  belongs_to :company

  validates :occurred_at, presence: true
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :until, ->(time) { where(occurred_at: ...time) }
  scope :during, ->(range) { where(occurred_at: range) }

  # What each company's limit was immediately before `time`. A company with no
  # entry yet is absent from the result: nothing has been recorded for it, which
  # the caller resolves from the live rows rather than assuming zero.
  def self.state_at(time)
    where(id: select("DISTINCT ON (company_id) id")
            .until(time)
            .order(:company_id, occurred_at: :desc, id: :desc))
      .pluck(:company_id, :max_sessions)
      .to_h
  end

  def self.record!(company_id:, max_sessions:, occurred_at: Time.current)
    create!(company_id: company_id, max_sessions: max_sessions, occurred_at: occurred_at)
  end
end
