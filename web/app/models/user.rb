# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  has_secure_password

  enumerize :status, in: %i[active suspended archived], default: :active, predicates: true, scope: true

  # Associations
  belongs_to :company
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Scopes
  scope :for_company, ->(company) { where(company: company) }

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end
end
