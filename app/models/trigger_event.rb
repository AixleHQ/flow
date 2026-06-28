# frozen_string_literal: true

# A normalized, persisted record that "something happened" — the single shape
# every trigger source collapses into (CloudEvents-style attribute model). It
# doubles as the TRANSACTIONAL OUTBOX: internal producers persist an event as
# relay_state "pending" inside the same transaction as their domain write, and
# OutboxRelay sweeps anything left pending past a grace window (a crash victim).
# See TriggerEngine for how events are produced and dispatched to workflows.
class TriggerEvent < ApplicationRecord
  belongs_to :project, optional: true
  belongs_to :company, optional: true
  belongs_to :board_task, optional: true
  belongs_to :actor, class_name: "User", optional: true
  has_many :trigger_dispatches, dependent: :destroy

  validates :event_type, presence: true

  # Relay lifecycle: pending → dispatching (claimed) → dispatched (done) |
  # failed (gave up after retries). A "dispatching" row whose router crashed is
  # re-swept once it ages past the grace window.
  RELAY_STATES = %w[pending dispatching dispatched failed].freeze
  # How long to let the inline dispatch finish before the relay treats a
  # pending/dispatching event as a crash victim and sweeps it.
  RELAY_GRACE = 2.minutes
  # Stop re-dispatching an event whose routing keeps RAISING, so one poison event
  # can't churn forever. High enough (~33h at the grace cadence) that a long
  # transient outage is ridden out, not buried.
  RELAY_MAX_ATTEMPTS = 1000

  # event_type conventions (reverse-DNS-ish):
  #   board.column.auto_triggered   — task entered a column with an auto binding
  #   board.task.gate_resolved      — a gate resolved (or was removed)
  #   workflow.manual_requested     — user pressed the manual trigger button
  #   slack.message                 — inbound Slack message via the gateway
  #   webhook.received              — generic inbound webhook via the gateway
  scope :recent, -> { order(created_at: :desc) }

  # Events the relay should (re)dispatch: pending past the grace window and not
  # yet exhausted. Ordered by id (monotonic) so older events drain first.
  scope :stuck_for_relay, ->(now = Time.current) {
    where(relay_state: %w[pending dispatching])
      .where(relay_attempts: ...RELAY_MAX_ATTEMPTS)
      .where(created_at: ..(now - RELAY_GRACE))
      .order(:id)
  }
end
