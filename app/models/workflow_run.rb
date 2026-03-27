# frozen_string_literal: true

class WorkflowRun < ApplicationRecord
  include WorkflowRunStateMachine
  extend Enumerize

  belongs_to :workflow
  belongs_to :project
  belongs_to :user
  belongs_to :board_task, optional: true, touch: true

  has_many :step_runs, dependent: :destroy
  has_many :workflow_run_assets, dependent: :destroy

  enumerize :mode, in: %i[interactive non_interactive mixed], default: :interactive, predicates: true

  validates :mode, presence: true

  scope :active, -> { where(state: %w[pending running paused]) }
  scope :for_project_in_period, ->(project, since) { where(project: project, created_at: since..) }
  scope :for_user_in_project, ->(project, user, since) { where(project: project, user: user, created_at: since..) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[state mode project_id user_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def can_run_non_interactive?
    workflow.steps.not_deleted.all?(&:allow_non_interactive)
  end

  def step_auto_run?(step_id)
    override = step_overrides[step_id.to_s]
    return override["auto_run"] unless override.nil?

    nil
  end

  def current_step_run
    step_runs.where(state: %w[pending running waiting_input]).order(:created_at).last
  end

  # Latest failed step the user may retry via API (current_step_run excludes failed — that caused 404 on retry).
  def latest_failed_step_run
    step_runs.failed.order(updated_at: :desc).first
  end
end
