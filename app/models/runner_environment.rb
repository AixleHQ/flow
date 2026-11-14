# frozen_string_literal: true

# One place a runner executes sessions (docs/design/agent-runtimes/DESIGN.md
# §2.2). In v1 so far the only entry path is a `manual` machine registering
# through the runner gateway (§5.2), which creates the row `registered`;
# unregistering marks it `gone`. A machine whose `env.reset` failed after a
# session, or whose refresh token was reused (Runners::Credentials.rotate!), is
# `failed` (Runners::Machines.fail!), with the reason in `state_reason`, and
# takes no session until it is returned to service (Runners::Machines.return_to_service!):
# an `env.reset` runs on it while it is `resetting`, and it is `registered` and
# free again once that succeeds, or `failed` with the new reason. The rest of
# the §5.2 state machine arrives with Runners::Allocator.
#
# `consecutive_failures` counts the failed sessions in a row on the machine; a
# session that ends well sets it back to 0, and `runners.max_consecutive_failures`
# of them take the machine out of rotation (§7.2).
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
# `auto_update` is false for a machine configured with `aixle-runner configure
# --no-auto-update`: it is never offered an update (Runners::Release.update_for,
# §14.4).
class RunnerEnvironment < ApplicationRecord
  extend Enumerize

  # Prefixed: origin and state share the value `registered`.
  enumerize :origin, in: %i[registered], predicates: { prefix: true }
  enumerize :state, in: %i[registered resetting failed gone], predicates: true

  # §2.5: a machine not heard for this long is offline.
  ONLINE_WINDOW = 90.seconds

  belongs_to :runner
  belongs_to :company
  belongs_to :current_session, class_name: "TerminalSession", optional: true
  has_many :credentials, class_name: "RunnerCredential", inverse_of: :runner_environment

  scope :free, -> { where(state: "registered", current_session_id: nil) }
  scope :heard, ->(now = Time.current) { where(last_heartbeat_at: (now - ONLINE_WINDOW)..) }
  # Never heard, or last heard at or before `time`.
  scope :not_heard_since, ->(time) { where(last_heartbeat_at: nil).or(where(arel_table[:last_heartbeat_at].lteq(time))) }

  before_validation { self.company_id ||= runner&.company_id }

  validates :key, presence: true
  validates :origin, presence: true
  validates :state, presence: true
  # `aixle-runner configure --name`, the hostname by default (§2.2).
  validates :display_name, presence: true, if: :origin_registered?
  validates :display_name, :os, :arch, :runner_version, :protocol_version, length: { maximum: 255 }
  validate :facts_is_an_object
  validate :company_matches_runner, if: -> { runner && company_id }

  def heard?(now = Time.current, within: ONLINE_WINDOW)
    last_heartbeat_at.present? && last_heartbeat_at >= now - within
  end

  # How the machine shows on the runner page (§2.5): `resetting`, `failed` and
  # `gone` as they are; a `registered` one is `offline` unless it is heard, else `online`
  # holding a session and `idle` without one.
  def display_state(now = Time.current)
    return state.to_s unless registered?
    return "offline" unless heard?(now)

    current_session_id ? "online" : "idle"
  end

  private

  def facts_is_an_object
    errors.add(:facts, "must be an object") unless facts.is_a?(Hash)
  end

  def company_matches_runner
    errors.add(:company, "must be the runner's company") if company_id != runner.company_id
  end
end
