module CompanyStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    aasm :state do
      state :active, initial: true
      state :suspended
      state :archived

      event :suspend do
        transitions from: :active, to: :suspended
      end

      event :activate do
        transitions from: %i[suspended archived], to: :active
      end

      event :archive do
        transitions from: %i[active suspended], to: :archived
      end
    end
  end
end
