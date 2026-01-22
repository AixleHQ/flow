# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  has_secure_password

  enumerize :state, in: %i[active suspended archived], default: :active, predicates: true, scope: true
  enumerize :role, in: %i[collaborator admin super_admin], default: :collaborator, predicates: true, scope: true

  # Associations
  belongs_to :company, optional: true
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validate :super_admin_company_validation

  # Custom validations
  def super_admin_company_validation
    if super_admin?
      errors.add(:company_id, "must be nil for super_admin users") if company_id.present?
    else
      errors.add(:company_id, "must be present for non-super_admin users") if company_id.nil?
    end
  end


  # Scopes
  scope :for_company, ->(company) { where(company: company) }

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end
end
