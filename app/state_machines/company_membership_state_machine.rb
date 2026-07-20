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

    # Onboarding is PER COMPANY: the role differs, the chosen agents differ, and
    # the agent credential must differ (billing is per company). Joining a second
    # company therefore runs the whole flow again.
    aasm :onboarding_state, column: :onboarding_state do
      state :step1, initial: true
      state :step2
      state :step3
      state :step4
      state :completed

      event :go_next do
        transitions from: :step1, to: :step2
        transitions from: :step2, to: :step3
        transitions from: :step3, to: :step4, guard: :can_advance_to_authenticated?
      end

      event :go_previous do
        transitions from: :step2, to: :step1
        transitions from: :step3, to: :step2
        transitions from: :step4, to: :step3
      end

      event :viewer_advance, guard: :viewer? do
        transitions from: :step2, to: :step4
      end

      event :complete, guard: :can_complete_onboarding?, after: :set_onboarding_completed_at do
        transitions from: :step4, to: :completed
      end

      # A role change within a company can newly require an agent this membership
      # never connected (a viewer promoted to employee). Back to agent selection,
      # not step1 — the profile answers for this company still stand.
      event :reopen do
        transitions from: :completed, to: :step2
      end
    end

    validates :onboarding_state, inclusion: {
      in: %w[step1 step2 step3 step4 completed],
      message: "is not a valid onboarding state"
    }
  end
end
