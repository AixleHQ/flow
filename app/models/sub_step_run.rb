# frozen_string_literal: true

class SubStepRun < ApplicationRecord
  extend Enumerize

  belongs_to :step_run
  belongs_to :sub_step

  enumerize :state, in: %i[pending in_progress completed skipped], default: :pending,
                    predicates: true, scope: true

  after_save :broadcast_update!, if: :saved_change_to_state?

  private

  def broadcast_update!
    step_run.broadcast_update!
  rescue StandardError => e
    Rails.logger.warn("[SubStepRun#broadcast_update!] #{e.message}")
  end
end
