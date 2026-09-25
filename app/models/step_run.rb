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

  HISTORY_ERROR_LIMIT = 2_000

  # A retry is a new step run of the same step. It carries the tally — which
  # attempt it is and what the earlier ones failed with — so get_step_run can
  # tell an agent or a person more than "failed".
  def self.next_attempt!(workflow_run:, step:)
    earlier = workflow_run.step_runs.where(step: step).order(:id).to_a
    workflow_run.step_runs.create!(step: step, state: :pending, retry_count: earlier.size,
                                   error_history: earlier.filter_map(&:history_entry))
  end

  def history_entry
    return if error_message.blank?

    { "step_run_id" => id, "state" => state.to_s, "error_category" => error_category,
      "error" => error_message.truncate(HISTORY_ERROR_LIMIT), "at" => (completed_at || updated_at)&.iso8601 }.compact
  end

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

  # `reason` is what the session died of, when something diagnosed it — a spend
  # limit, a lost node. A cancelled step with an empty error_message reads as "someone
  # clicked cancel", which is exactly the wrong thing to tell a user whose account is
  # out of credit.
  def mark_cancelled!(reason = nil)
    update!(state: :cancelled, completed_at: Time.current,
            error_message: reason.presence || error_message)
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
