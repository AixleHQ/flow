# frozen_string_literal: true

class SessionAdmission < ApplicationRecord
  # Reasons a reservation is deliberately not making progress. None of them is
  # staleness, so the reapers must leave them alone (AD-7, AD-8).
  #
  # `runner_capacity` is a session on an external runner whose every machine is
  # busy (Runners::Allocator::RUNNER_CAPACITY): a wait like `cluster_capacity`,
  # for a machine instead of a pod. `runner_provisioning` is a session whose
  # environment the platform is building for it (Runners::Allocator::Pending).
  WAIT_REASONS = %w[concurrency_limit namespace_quota cluster_capacity runner_capacity runner_provisioning].freeze
  # The reasons the launch itself waits on, which a screen names.
  LAUNCH_WAITS = %w[namespace_quota cluster_capacity runner_capacity runner_provisioning].freeze

  belongs_to :terminal_session
  belongs_to :session_admission_pool
  has_many :session_runtime_operations, dependent: :destroy
  scope :unreleased, -> { where(released_at: nil) }
  scope :occupied, -> { unreleased.where.not(admitted_at: nil) }
  scope :waiting, -> { unreleased.where(wait_reason: WAIT_REASONS) }

  # Whether this reservation waits for a machine of its session's runner: every
  # machine is busy, or offline and not yet lapsed (Runners::Allocator).
  def waiting_for_runner_machine?
    wait_reason == "runner_capacity"
  end

  # Whether no launch has been dispatched for this reservation yet: it is still
  # queued, or granted but not claimed by the relay. Closing it needs no cleanup of
  # a runtime, so it is released at once.
  def unlaunched?
    admitted_at.nil? || (launch_state == "pending" && claimed_at.nil?)
  end

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
    return wait_reason if wait_reason.in?(LAUNCH_WAITS)
    return "starting" unless launch_state == "acknowledged"

    "running"
  end
end
