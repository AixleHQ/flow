# frozen_string_literal: true

# Audit + idempotency ledger row: a TriggerEvent was matched by a trigger and
# (attempted to) start a workflow run. The unique dedup_key is what makes a
# re-delivered/at-least-once event safe — a duplicate insert is rescued and the
# second launch is suppressed.
class TriggerDispatch < ApplicationRecord
  belongs_to :trigger_event
  belongs_to :trigger_binding, optional: true
  belongs_to :workflow_run, optional: true

  # Uniqueness is enforced by the DB unique index on dedup_key (not a model
  # validation): the index raises ActiveRecord::RecordNotUnique with no TOCTOU
  # race, which is exactly what TriggerEngine#fire_workflow rescues to suppress a
  # duplicate launch from at-least-once delivery.
  validates :dedup_key, presence: true

  STATUSES = %w[matched started skipped failed].freeze
end
