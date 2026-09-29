# frozen_string_literal: true

# IntegrationData — generic per-integration key/value store with optional TTL.
#
# Not Coder-specific: any integration that needs runtime state (locks, caches,
# sync cursors, etc.) can store typed JSON values here keyed by
# `(integration_id, key)`. Coder's `LockService` is the first consumer; it
# keys rows as `coder:workspace_lock:<workspace_name>`.
#
# Keys are unique per integration (`(integration_id, key)`). Coder workspace locks
# are additionally unique on the workspace id across integrations, because two
# integrations can reach the same pool of machines.
class IntegrationData < ApplicationRecord
  self.table_name = "integration_data"

  belongs_to :integration

  validates :key, presence: true

  scope :live,            -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired,         -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
  scope :with_key_prefix, ->(prefix) { where("key LIKE ?", "#{sanitize_sql_like(prefix)}%") }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
