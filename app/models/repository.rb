# frozen_string_literal: true

class Repository < ApplicationRecord
  belongs_to :scope, polymorphic: true
  belongs_to :integration

  validates :full_name, presence: true,
                        format: { with: %r{\A[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\z}, message: "must be in owner/repo format" }
  validates :full_name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :source_branch, presence: true
  validates :clone_url, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }

  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :for_integration, ->(integration) { where(integration: integration) }

  scope :visible_for_project, ->(project) {
    where(scope_type: "Company", scope_id: project.company_id)
      .or(where(scope_type: "Project", scope_id: project.id))
  }
  scope :visible_for_company, ->(company) { for_company(company) }

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  def repo_name
    full_name&.split("/")&.last
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[full_name source_branch is_private scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope integration]
  end
end
