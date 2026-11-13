# frozen_string_literal: true

# One place a runner executes sessions (docs/design/agent-runtimes/DESIGN.md
# §2.2). In v1 so far the only entry path is a `manual` machine registering
# through the runner gateway (§5.2), which creates the row `registered`;
# unregistering marks it `gone`. A machine whose `env.reset` failed after a
# session, or whose refresh token was reused (Runners::Credentials.rotate!), is
# `failed` (Runners::Machines.fail!), with the reason in `state_reason`, and
# takes no session until it is returned to service (task 11). The rest of the §5.2 state machine arrives with Runners::Allocator.
#
# `current_session` is the session that holds the machine (Runners::Machines):
# a `registered` machine without one is free. It is cleared once the machine
# has been reset after the session, and when it fails.
#
# `last_heartbeat_at` is the last time the platform heard from the machine
# (Runners::Liveness.record!). A `registered` machine heard within
# ONLINE_WINDOW, or executing a delivered op within its deadline (the host
# runner does not poll during an op, §6.7), is `reachable`; any other is
# offline and takes no new session (Runners::Machines).
#
# `auto_update` is false for a machine configured with `aixle-runner configure
# --no-auto-update`: it is never offered an update (Runners::Release.update_for,
# §14.4).
class RunnerEnvironment < ApplicationRecord
  extend Enumerize

  # Prefixed: origin and state share the value `registered`.
  enumerize :origin, in: %i[registered], predicates: { prefix: true }
  enumerize :state, in: %i[registered failed gone], predicates: true

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
  # Executing an op it was delivered, within the op's deadline.
  scope :executing_op, ->(now = Time.current) {
    where(id: RunnerOperation.delivered_before_deadline(now).select(:runner_environment_id))
  }
  scope :reachable, ->(now = Time.current) { heard(now).or(executing_op(now)) }

  before_validation { self.company_id ||= runner&.company_id }

  validates :key, presence: true
  validates :origin, presence: true
  validates :state, presence: true
  # `aixle-runner configure --name`, the hostname by default (§2.2).
  validates :display_name, presence: true, if: :origin_registered?
  validates :display_name, :os, :arch, :runner_version, :protocol_version, length: { maximum: 255 }
  validate :facts_is_an_object
  # Reserved for an ephemeral registration (§6.3), which v1 refuses.
  validates :ephemeral, inclusion: { in: [ false ] }
  validate :company_matches_runner, if: -> { runner && company_id }

  def heard?(now = Time.current)
    last_heartbeat_at.present? && last_heartbeat_at >= now - ONLINE_WINDOW
  end

  private

  def facts_is_an_object
    errors.add(:facts, "must be an object") unless facts.is_a?(Hash)
  end

  def company_matches_runner
    errors.add(:company, "must be the runner's company") if company_id != runner.company_id
  end
end
