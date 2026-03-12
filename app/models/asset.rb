# frozen_string_literal: true

class Asset < ApplicationRecord
  belongs_to :scope, polymorphic: true
  belongs_to :created_by, class_name: "User"
  belongs_to :step_run, optional: true
  belongs_to :terminal_session, optional: true

  has_many :versions, class_name: "AssetVersion", dependent: :destroy, inverse_of: :asset

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id folder], message: "already exists in this scope" }
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[active pending_review dismissed] }
  validates :folder, format: { with: /\A[a-z0-9_-]+\z/, message: "only lowercase letters, numbers, hyphens, underscores" },
                     allow_blank: true

  scope :active, -> { where(deleted_at: nil, status: "active") }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :pending_review, -> { where(status: "pending_review") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :for_company, ->(company) { active.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { active.where(scope_type: "Project", scope_id: project.id) }
  scope :accessible_from_project, ->(project) {
    active
      .where(scope_type: "Project", scope_id: project.id)
      .or(active.where(scope_type: "Company", scope_id: project.company_id))
  }
  scope :downloadable_from_project, ->(project) {
    where(deleted_at: nil)
      .where(status: %w[active pending_review])
      .where(scope_type: "Project", scope_id: project.id)
      .or(
        where(deleted_at: nil)
          .where(status: %w[active pending_review])
          .where(scope_type: "Company", scope_id: project.company_id)
      )
  }
  scope :scoped_to_project, ->(project) {
    where(scope_type: "Project", scope_id: project.id)
      .or(where(scope_type: "Company", scope_id: project.company_id))
  }

  scope :visible_for_project, ->(project) {
    active.where(scope_type: "Project", scope_id: project.id)
          .or(active.where(scope_type: "Company", scope_id: project.company_id))
  }
  scope :visible_for_company, ->(company) { for_company(company) }

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  def latest_version
    versions.order(version: :desc).first
  end

  def resolve_version(version_number = nil)
    if version_number.present?
      versions.find_by!(version: version_number)
    else
      latest_version or raise ActiveRecord::RecordNotFound, "No versions for asset"
    end
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    raise ActiveRecord::RecordNotFound, "Asset is not deleted" unless deleted?

    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name folder scope_type status terminal_session_id deleted_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope created_by terminal_session versions]
  end
end
