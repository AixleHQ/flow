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

  # What this reservation is ACTUALLY waiting on, for the screens that have to
  # tell a person why nothing is happening yet.
  #
  # Neither the session state nor `wait_reason` can answer that alone. A session
  # stays in `queued` from the moment the row is written until the container
  # workflow's first activity calls `start!` — right through dispatch — so the
  # state covers both "nobody has a slot for you" and "your slot is granted, the
  # container is coming up". And `wait_reason` defaults to "concurrency_limit" at
  # insert, so it agrees with whichever reading you already had. Screens took the
  # pair to mean a full pool: an authentication session granted its slot in one
  # second still told the user to wait for capacity.
  def launch_phase
    return "queued_for_slot" if admitted_at.nil?
    return wait_reason if wait_reason.in?(%w[namespace_quota cluster_capacity])
    return "starting" unless launch_state == "acknowledged"

    "running"
  end
end
