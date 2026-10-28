# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.5.
module RunnerStateMachine
  extend ActiveSupport::Concern

  HEALTH_STATES = %i[pending connected degraded unreachable].freeze

  included do
    include AASM

    # whiny_persistence: a state that fails to save raises instead of returning
    # false unnoticed. A lost revoke would be the worst case.
    aasm column: :status, whiny_persistence: true do
      state :pending, initial: true
      state :connected
      state :degraded
      state :unreachable
      state :disabled
      state :revoked

      event :mark_connected do
        transitions from: %i[pending degraded unreachable], to: :connected, after: :clear_status_reason
      end

      event :mark_degraded do
        transitions from: %i[pending connected unreachable], to: :degraded, after: :record_status_reason
      end

      event :mark_unreachable do
        transitions from: %i[pending connected degraded], to: :unreachable, after: :record_status_reason
      end

      event :disable do
        transitions from: HEALTH_STATES, to: :disabled, after: -> { self.disabled_at = Time.current }
      end

      # Back to pending, not connected: nothing checked the runner while it was disabled.
      event :enable do
        transitions from: :disabled, to: :pending, after: -> { self.disabled_at = nil }
      end

      event :revoke do
        transitions from: %i[pending connected degraded unreachable disabled], to: :revoked,
                    after: -> { self.revoked_at = Time.current }
      end
    end
  end

  # Deleting is a soft delete that revokes in the same write, so a deleted
  # runner is revoked in the data and not only in reads.
  def soft_delete!
    transaction do
      revoke unless revoked?
      self.deleted_at = Time.current
      save!
    end
  end

  def deleted?
    deleted_at.present?
  end

  private

  def record_status_reason(reason = nil)
    self.status_reason = reason
  end

  def clear_status_reason(*)
    self.status_reason = nil
  end
end
