# frozen_string_literal: true

class WorkflowRun < ApplicationRecord
  include WorkflowRunStateMachine
  extend Enumerize

  belongs_to :workflow
  belongs_to :project
  belongs_to :user

  has_many :step_runs, dependent: :destroy
  has_many :workflow_run_assets, dependent: :destroy

  enumerize :mode, in: %i[interactive non_interactive mixed], default: :interactive, predicates: true

  validates :mode, presence: true

  scope :active, -> { where(state: %w[pending running paused]) }

  def can_run_non_interactive?
    workflow.steps.all?(&:allow_non_interactive)
  end

  def step_auto_run?(step_id)
    override = step_overrides[step_id.to_s]
    return override["auto_run"] unless override.nil?

    nil
  end

  def current_step_run
    step_runs.where(state: %w[pending running waiting_input]).order(:created_at).last
  end
end
