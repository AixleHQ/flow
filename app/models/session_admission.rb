# frozen_string_literal: true

class SessionAdmission < ApplicationRecord
  # Reasons a reservation is deliberately not making progress. None of them is
  # staleness, so the reapers must leave them alone (AD-7, AD-8).
  WAIT_REASONS = %w[concurrency_limit namespace_quota cluster_capacity].freeze

  belongs_to :terminal_session
  belongs_to :session_admission_pool
  has_many :session_runtime_operations, dependent: :destroy
  scope :unreleased, -> { where(released_at: nil) }
  scope :occupied, -> { unreleased.where.not(admitted_at: nil) }
  scope :waiting, -> { unreleased.where(wait_reason: WAIT_REASONS) }
end
