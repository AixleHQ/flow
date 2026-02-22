# frozen_string_literal: true

class Workflow < ApplicationRecord
  belongs_to :scope, polymorphic: true

  has_many :steps, dependent: :destroy
  has_many :runs, class_name: "WorkflowRun", dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id], conditions: -> { where(deleted_at: nil) },
                                 message: "already exists in this scope" }

  scope :active, -> { where(deleted_at: nil) }
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  def self.merged_for_project(project)
    active.where(scope_type: "Project", scope_id: project.id)
          .or(active.where(scope_type: "Company", scope_id: project.company_id))
  end

  def self.merged_for_company(company)
    active.for_company(company)
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def has_active_runs?
    runs.where(state: %w[running paused]).exists?
  end

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name description scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end
end
