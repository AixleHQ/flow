# frozen_string_literal: true

class TaskWait < ApplicationRecord
  extend Enumerize

  belongs_to :board_task
  belongs_to :creator, class_name: "User"

  enumerize :wait_type, in: %i[github_checks_completed], predicates: true
  enumerize :status, in: %i[pending resolved], default: :pending, predicates: true, scope: true

  validates :wait_type, presence: true
  validates :status, presence: true

  scope :pending,  -> { where(status: "pending") }
  scope :resolved, -> { where(status: "resolved") }

  # Scope waits by the repo_full_name stored in their metadata JSONB.
  # Apply after for_repository to keep the result set narrow.
  scope :for_repo_full_name, ->(repo_full_name) {
    where("metadata->>'repo_full_name' = ?", repo_full_name)
  }

  # Scope waits by PR number only — used after the query is already scoped to
  # the correct project(s) via for_repository.
  scope :for_github_pr_number, ->(pr_number) {
    where(wait_type: "github_checks_completed")
      .where("(metadata->>'pr_number')::int = ?", pr_number.to_i)
  }

  # Scope waits to tasks whose boards belong to projects connected to the given
  # repository. Handles both project-scoped and company-scoped repositories.
  scope :for_repository, ->(repo_full_name) {
    project_ids_from_project_repos = Repository
      .where(full_name: repo_full_name, scope_type: "Project")
      .pluck(:scope_id)

    company_ids = Repository
      .where(full_name: repo_full_name, scope_type: "Company")
      .pluck(:scope_id)

    project_ids_from_company_repos = company_ids.any? ?
      Project.where(company_id: company_ids).pluck(:id) : []

    all_project_ids = (project_ids_from_project_repos + project_ids_from_company_repos).uniq

    joins(board_task: { board_column: { board: :project } })
      .where(projects: { id: all_project_ids })
  }
end
