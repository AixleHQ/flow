module UserStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    aasm :state do
      state :draft, initial: true
      state :active
      state :archived

      event :activate do
        transitions from: :draft, to: :active
      end

      event :deactivate do
        transitions from: :active, to: :archived
      end
    end
  end
end
