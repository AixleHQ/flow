module Specification::VersionStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    aasm :state do
      state :draft, initial: true
      state :processing
      state :cancelled
      state :ready
      state :failed

      event :start do
        transitions from: [ :draft, :cancelled ], to: :processing
      end

      event :process do
        transitions from: :processing, to: :ready
      end

      event :cancel do
        transitions from: :processing, to: :cancelled
        after do
          # TemporalService.start_workflow(WorkflowService.specification_version_cancel, self.id)
        end
      end

      event :fail do
        transitions from: [ :draft, :processing, :ready ], to: :failed
      end
    end
  end
end
