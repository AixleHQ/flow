# frozen_string_literal: true

module TerminalSessionStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :not_started, initial: true
      state :running
      state :ready
      state :finished
      state :failed

      event :start do
        transitions from: :not_started, to: :running, after: :on_started
      end

      event :mark_ready do
        transitions from: %i[not_started running], to: :ready, after: :on_ready
      end

      event :finish do
        transitions from: %i[not_started running ready], to: :finished, after: :on_finished
      end

      event :fail do
        transitions from: %i[not_started running ready], to: :failed, after: :on_failed
      end
    end
  end
end
