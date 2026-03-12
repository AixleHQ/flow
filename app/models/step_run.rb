# frozen_string_literal: true

class StepRun < ApplicationRecord
  extend Enumerize

  belongs_to :workflow_run
  belongs_to :step
  belongs_to :terminal_session, optional: true

  has_many :sub_step_runs, dependent: :destroy
  has_many :produced_workflow_run_assets, class_name: "WorkflowRunAsset", foreign_key: :produced_by_step_run_id,
                                         dependent: :nullify, inverse_of: :produced_by_step_run

  enumerize :state, in: %i[pending running waiting_input completed failed skipped cancelled], default: :pending,
                    predicates: true, scope: true

  scope :ordered, -> { joins(:step).order("steps.position ASC") }

  def mark_running!
    update!(state: :running, started_at: Time.current)
    broadcast_update!
  end

  def mark_waiting!
    update!(state: :waiting_input)
    broadcast_update!
  end

  def mark_completed!
    update!(state: :completed, completed_at: Time.current)
    broadcast_update!
  end

  def mark_failed!(message = nil)
    update!(state: :failed, completed_at: Time.current, error_message: message)
    broadcast_update!
  end

  def mark_skipped!(reason = nil)
    update!(state: :skipped, completed_at: Time.current, skip_reason: reason)
    broadcast_update!
  end

  def mark_cancelled!
    update!(state: :cancelled, completed_at: Time.current)
    broadcast_update!
  end

  def create_sub_step_runs!
    step.sub_steps.order(:position).each do |sub_step|
      sub_step_runs.find_or_create_by!(sub_step: sub_step) do |ssr|
        ssr.state = :pending
      end
    end
  end

  def retryable?
    failed? && (step.max_retries.to_i > retry_count.to_i)
  end

  def retry_count
    self[:retry_count] || 0
  end

  def broadcast_update!
    WorkflowRunChannel.broadcast_step_update(workflow_run, self)
  rescue StandardError => e
    Rails.logger.warn("[StepRun#broadcast_update!] #{e.message}")
  end
end
