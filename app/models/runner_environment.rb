# frozen_string_literal: true

# One place a runner executes sessions (docs/design/agent-runtimes/DESIGN.md
# §2.2). In v1 so far the only entry path is a `manual` machine registering
# through the runner gateway (§5.2), which creates the row `registered`;
# unregistering marks it `gone`. A machine whose `env.reset` failed after a
# session, whose check-in reported missing prerequisites or whose refresh token
# was reused (Runners::Credentials.rotate!) is `failed` (Runners::Machines.fail!),
# with the reason in `state_reason`, and takes no session. `failed` is final:
# its credentials stop working, and it leaves by a Revoke (`gone`) and is
# registered again with Add machine. A session's outcome never fails a machine.
# The states and their events are RunnerEnvironmentStateMachine's; the rest of
# the §5.2 state machine arrives with Runners::Allocator.
#
# `current_session` is the session that holds the machine (Runners::Machines):
# a `registered` machine without one is free. It is cleared once the machine
# has been reset after the session, and when it fails.
#
# `last_heartbeat_at` is the last time the platform heard from the machine
# (Runners::Liveness.record!): its polls, and its heartbeats while it runs an
# op (§6.7). A `registered` machine heard within ONLINE_WINDOW is online; any
# other is offline and takes no new session (Runners::Machines).
#
# `first_seen_ip` is the address the machine registered from, recorded once, and
# `created_by` the user who minted its registration token ("Add machine"). A
# machine registered before they were recorded has neither (§12.2).
#
# `auto_update` is false for a machine configured with `aixle-runner configure
# --no-auto-update`: it is never offered an update (Runners::Release.update_for,
# §14.4).
class RunnerEnvironment < ApplicationRecord
  extend Enumerize
  include RunnerEnvironmentStateMachine

  # Prefixed: origin and state share the value `registered`. The states are
  # RunnerEnvironmentStateMachine's.
  enumerize :origin, in: %i[registered], predicates: { prefix: true }

  # §2.5: a machine not heard for this long is offline.
  ONLINE_WINDOW = 90.seconds

  belongs_to :runner
  belongs_to :company
  belongs_to :current_session, class_name: "TerminalSession", optional: true
  # The user who minted the registration token the machine registered with.
  belongs_to :created_by, class_name: "User", optional: true
  has_many :credentials, class_name: "RunnerCredential", inverse_of: :runner_environment

  scope :free, -> { where(state: "registered", current_session_id: nil) }
  scope :holding_session, -> { where.not(current_session_id: nil) }
  # Held by a session whose cleanup will never run (TerminalSession.cleanup_abandoned).
  scope :held_by_abandoned_session, -> { where(current_session_id: TerminalSession.cleanup_abandoned.select(:id)) }
  scope :heard, ->(now = Time.current) { where(last_heartbeat_at: (now - ONLINE_WINDOW)..) }
  # Never heard, or last heard at or before `time`.
  scope :not_heard_since, ->(time) { where(last_heartbeat_at: nil).or(where(arel_table[:last_heartbeat_at].lteq(time))) }

  before_validation { self.company_id ||= runner&.company_id }
  # A session taking or leaving the machine is told to the relay (runner-relay.md §8.1).
  # Writes that skip callbacks (`update_all`) send it themselves.
  after_save :signal_relay_machine_session, if: :saved_change_to_current_session_id?

  validates :key, presence: true
  validates :origin, presence: true
  validates :state, presence: true
  # `aixle-runner configure --name`, the hostname by default (§2.2).
  validates :display_name, presence: true, if: :origin_registered?
  validates :display_name, :os, :arch, :runner_version, :protocol_version, :first_seen_ip, length: { maximum: 255 }
  validate :facts_is_an_object
  validate :company_matches_runner, if: -> { runner && company_id }

  # Holds a session. A `registered` machine that is not busy is free.
  def busy?
    current_session_id.present?
  end

  # The machine left for good by a Revoke on the runner page, not by
  # `aixle-runner unregister`. A machine revoked before the reason was recorded
  # has none and reads as unregistered.
  def revoked_by_operator?
    gone? && state_reason == REVOKED
  end

  # The machine takes no more calls from the platform: it left (`gone`) or it
  # failed, and nothing but a Revoke and a new Add machine follows either.
  def out_of_service?
    gone? || failed?
  end

  # What the machine's last report says keeps it from running sessions (the
  # host runner's preflight, DESIGN.md §6.8: no reachable Docker daemon, too
  # little disk), or nil when the report has no failure.
  def preflight_failure
    facts["preflight_error"].presence if facts.is_a?(Hash)
  end

  def heard?(now = Time.current, within: ONLINE_WINDOW)
    last_heartbeat_at.present? && last_heartbeat_at >= now - within
  end

  # Not heard for `period` or more. A machine never heard counts from its creation.
  def silent_for?(period, now = Time.current)
    (last_heartbeat_at || created_at) <= now - period
  end

  # How the machine shows on the runner page (§2.5): `failed` and `gone` as
  # they are; a `registered` one is `offline` unless it is heard, else `online`
  # holding a session and `idle` without one.
  def display_state(now = Time.current)
    return state.to_s unless registered?
    return "offline" unless heard?(now)

    busy? ? "online" : "idle"
  end

  private

  def signal_relay_machine_session
    Runners::RelaySignals.machine_session(id, current_session_id)
  end

  def facts_is_an_object
    errors.add(:facts, "must be an object") unless facts.is_a?(Hash)
  end

  def company_matches_runner
    errors.add(:company, "must be the runner's company") if company_id != runner.company_id
  end
end
