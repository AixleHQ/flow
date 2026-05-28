# frozen_string_literal: true

class StepRun < ApplicationRecord
  extend Enumerize

  belongs_to :workflow_run, counter_cache: true
  belongs_to :step
  belongs_to :terminal_session, optional: true

  has_many :sub_step_runs, dependent: :destroy
  has_many :produced_workflow_run_assets, class_name: "WorkflowRunAsset", foreign_key: :produced_by_step_run_id,
                                         dependent: :nullify, inverse_of: :produced_by_step_run

  enumerize :state, in: %i[pending running waiting_input completed failed skipped cancelled], default: :pending,
                    predicates: true, scope: true

  broadcasts_to :workflow_run, on: :update

  scope :ordered, -> { joins(:step).order("steps.position ASC") }

  def mark_running!
    update!(state: :running, started_at: Time.current, error_message: nil)
  end

  def mark_waiting!
    update!(state: :waiting_input)
  end

  def mark_completed!
    update!(state: :completed, completed_at: Time.current)
  end

  def mark_failed!(message = nil, error_category: nil)
    update!(state: :failed, completed_at: Time.current, error_message: message,
            error_category: error_category&.to_s)
  end

  def mark_skipped!(reason = nil)
    update!(state: :skipped, completed_at: Time.current, skip_reason: reason)
  end

  def mark_cancelled!
    update!(state: :cancelled, completed_at: Time.current)
  end

  def create_sub_step_runs!
    step.sub_steps.active.each do |sub_step|
      sub_step_runs.find_or_create_by!(sub_step: sub_step) do |ssr|
        ssr.state = :pending
      end
    end
  end

  def retryable?
    failed?
  end

  def retry_count
    self[:retry_count].to_i
  end
end
