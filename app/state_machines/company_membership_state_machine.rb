module CompanyMembershipStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    # Per-company membership lifecycle
    aasm :state do
      state :invited, initial: true
      state :active
      state :suspended
      state :revoked

      # `before` (not `after`) so accepted_at is persisted in the same save as the state change
      event :accept, before: :set_accepted_at do
        transitions from: :invited, to: :active
      end

      event :suspend do
        transitions from: :active, to: :suspended
      end

      event :reactivate do
        transitions from: :suspended, to: :active
      end

      event :revoke do
        transitions from: %i[invited active suspended], to: :revoked
      end

      # Re-inviting a previously removed member reuses the row (user+company is
      # unique). Going through a proper event keeps callbacks/token semantics.
      event :reinvite do
        transitions from: :revoked, to: :invited
      end
    end
  end
end
