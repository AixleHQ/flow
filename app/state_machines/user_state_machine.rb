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

      event :suspend do
        transitions from: :active, to: :suspended
      end

      event :archive do
        transitions from: %i[active suspended pending], to: :archived
      end

      event :mark_pending do
        transitions from: :active, to: :pending
      end
    end

    # Onboarding state machine
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

      event :complete, guard: :can_complete_onboarding?, after: :set_onboarding_completed_at do
        transitions from: :step4, to: :completed
      end

      # Accepting an invitation into a company where the user needs setup they
      # never did re-opens onboarding (see User#needs_agent_setup?): a
      # viewer-everywhere user skipped the agent steps, and gaining a role that
      # can run things otherwise leaves them at empty agent pickers forever.
      # Back to step2 (Select Agents), not step1 — their profile answers stand.
      event :reopen do
        transitions from: :completed, to: :step2
      end
    end

    # Validation for onboarding_state
    validates :onboarding_state, inclusion: {
      in: %w[step1 step2 step3 step4 completed],
      message: "is not a valid onboarding state"
    }
  end
end
