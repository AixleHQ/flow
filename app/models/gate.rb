# frozen_string_literal: true

class Gate < ApplicationRecord
  extend Enumerize

  belongs_to :board_task
  belongs_to :creator, class_name: "User"

  enumerize :gate_type, in: %i[github_checks_completed github_workflow_completed gitlab_pipeline_completed], predicates: true
  enumerize :status, in: %i[pending resolved], default: :pending, predicates: true, scope: true

  validates :gate_type, presence: true
  validates :status, presence: true

  scope :pending,  -> { where(status: "pending") }
  scope :resolved, -> { where(status: "resolved") }

  # Scope gates by the repo_full_name stored in their metadata JSONB.
  # Apply after for_repository to keep the result set narrow.
  scope :for_repo_full_name, ->(repo_full_name) {
    where("metadata->>'repo_full_name' = ?", repo_full_name)
  }

  # Scope gates by PR number only — used after the query is already scoped to
  # the correct project(s) via for_repository.
  scope :for_github_pr_number, ->(pr_number) {
    where(gate_type: "github_checks_completed")
      .where("(metadata->>'pr_number')::int = ?", pr_number.to_i)
  }

  # Scope gates by workflow run ID only — used after the query is already
  # scoped to the correct project(s) via for_repository.
  scope :for_github_workflow_run_id, ->(run_id) {
    where(gate_type: "github_workflow_completed")
      .where("(metadata->>'run_id')::bigint = ?", run_id.to_i)
  }

  # Scope gates by GitLab pipeline ID only — used after the query is already
  # scoped to the correct project(s) via for_repository.
  scope :for_gitlab_pipeline_id, ->(pipeline_id) {
    where(gate_type: "gitlab_pipeline_completed")
      .where("(metadata->>'pipeline_id')::bigint = ?", pipeline_id.to_i)
  }

  # Scope gates to tasks whose boards belong to projects connected to the given
  # repository. Handles both project-scoped and company-scoped repositories.
  scope :for_repository, ->(repo_full_name) {
    joins(board_task: { board_column: { board: :project } })
      .where(projects: { id: Repository.project_ids_for(repo_full_name) })
  }
end
