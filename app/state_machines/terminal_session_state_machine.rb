# frozen_string_literal: true

module TerminalSessionStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :not_started, initial: true
      state :queued
      state :cancelled
      state :running
      state :ready
      state :finishing
      state :finished
      state :failed

      event :start do
        transitions from: %i[not_started queued], to: :running, after: :on_started
      end

      event :mark_ready do
        transitions from: %i[not_started running], to: :ready, after: :on_ready
      end

      event :start_finishing do
        transitions from: %i[not_started running ready], to: :finishing, after: :on_finishing
      end

      event :finish do
        transitions from: :finishing, to: :finished, after: :on_finished
      end

      event :fail do
        transitions from: %i[not_started queued running ready finishing], to: :failed, after: :on_failed
      end
    end
  end
end
