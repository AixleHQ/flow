# frozen_string_literal: true

module UserStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    # User account state machine
    aasm :state do
      state :active, initial: true
      state :pending
      state :suspended
      state :archived

      event :activate do
        transitions from: %i[pending suspended archived], to: :active
      end

      event :suspend, after_commit: :revoke_live_access! do
        transitions from: :active, to: :suspended
      end

      event :archive, after_commit: :revoke_live_access! do
        transitions from: %i[active suspended pending], to: :archived
      end

      event :mark_pending do
        transitions from: :active, to: :pending
      end
    end
  end
end
