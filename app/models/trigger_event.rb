# frozen_string_literal: true

# A normalized, persisted record that "something happened" — the single shape
# every trigger source collapses into (CloudEvents-style attribute model).
# See TriggerEngine for how events are produced and dispatched to workflows.
class TriggerEvent < ApplicationRecord
  belongs_to :project, optional: true
  belongs_to :board_task, optional: true
  has_many :trigger_dispatches, dependent: :destroy

  validates :event_type, presence: true

  # event_type conventions (reverse-DNS-ish):
  #   board.column.auto_triggered   — task entered a column with an auto binding
  #   board.task.wait_resolved      — a task_wait resolved (or was removed)
  #   workflow.manual_requested     — user pressed the manual trigger button
  #   slack.message                 — inbound Slack message via the gateway
  #   webhook.received              — generic inbound webhook via the gateway
  scope :recent, -> { order(created_at: :desc) }
end
