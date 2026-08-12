# frozen_string_literal: true

class WorkflowRun < ApplicationRecord
  include WorkflowRunStateMachine
  extend Enumerize

  belongs_to :workflow
  belongs_to :project
  belongs_to :user
  belongs_to :board_task, optional: true, touch: true
  belongs_to :failed_agent_credential, class_name: "AgentCredential", optional: true

  has_many :step_runs, dependent: :destroy
  has_many :workflow_run_assets, dependent: :destroy

  enumerize :mode, in: %i[interactive non_interactive mixed], default: :interactive, predicates: true

  validates :mode, presence: true

  broadcasts_to ->(run) { run }, on: :update
  after_commit :broadcast_run_list_update, on: :update

  scope :active, -> { where(state: %w[pending running paused]) }
  scope :for_project_in_period, ->(project, since) { where(project: project, created_at: since..) }
  scope :for_user_in_project, ->(project, user, since) { where(project: project, user: user, created_at: since..) }
  scope :for_user_in_period, ->(user, since) { where(user: user, created_at: since..) }

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
    step_runs.where(state: :failed).order(updated_at: :desc).first
  end

  def mark_quota_failed!(credential_id:)
    update!(failure_reason: "quota_exceeded", failed_agent_credential_id: credential_id)
  end

  private

  def broadcast_run_list_update
    return unless project_id.present?

    ActionCable.server.broadcast("workflow_run_list:project:#{project_id}", {
      type: "run_update",
      run: {
        id: id,
        workflowId: workflow_id,
        workflowName: workflow&.name,
        state: state,
        mode: mode.to_s,
        stepsCompleted: step_runs.where(state: :completed).count,
        stepsTotal: step_runs_count,
        startedAt: started_at&.iso8601,
        completedAt: completed_at&.iso8601,
        createdAt: created_at.iso8601
      }
    })
  end
end
