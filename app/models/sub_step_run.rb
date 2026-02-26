# frozen_string_literal: true

class SubStepRun < ApplicationRecord
  extend Enumerize

  belongs_to :step_run
  belongs_to :sub_step

  enumerize :state, in: %i[pending in_progress completed skipped], default: :pending,
                    predicates: true, scope: true

  after_save :broadcast_update!, if: :saved_change_to_state?
  after_save :auto_finish_session!, if: :saved_change_to_state?

  private

  def broadcast_update!
    step_run.broadcast_update!
  rescue StandardError => e
    Rails.logger.warn("[SubStepRun#broadcast_update!] #{e.message}")
  end

  def auto_finish_session!
    return unless all_sub_steps_done?

    session = step_run.terminal_session
    return unless session&.mode == "non_interactive"
    return unless session.may_finish?

    Rails.logger.info("[SubStepRun] All sub-steps done for step_run=#{step_run.id}, finishing session #{session.id}")
    session.request_finish!
  rescue StandardError => e
    Rails.logger.warn("[SubStepRun#auto_finish_session!] #{e.message}")
  end

  def all_sub_steps_done?
    step_run.sub_step_runs.reload.all? { |ssr| ssr.completed? || ssr.skipped? }
  end
end
