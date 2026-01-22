# frozen_string_literal: true

class Project < ApplicationRecord
  extend Enumerize

  # Constants
  ARTIFACTS_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze

  enumerize :state, in: %i[active paused archived], default: :active, predicates: true, scope: true

  # Associations
  belongs_to :company
  belongs_to :owner, class_name: "User", inverse_of: :owned_projects
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborators, through: :project_collaborators, source: :user

  # Validations
  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :slug, presence: true,
                   uniqueness: { scope: :company_id },
                   format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :preferred_artifacts_language, inclusion: { in: ARTIFACTS_LANGUAGES }, allow_nil: false
  validate :owner_belongs_to_company

  # Callbacks
  before_validation :generate_slug, on: :create

  # Scopes
  scope :for_company, ->(company) { where(company: company) }
  scope :for_user, ->(user) { where(owner: user).or(where(id: user.collaborated_projects.select(:id))) }

  # Add a user as collaborator
  def add_collaborator(user)
    project_collaborators.find_or_create_by!(user: user)
  end

  # Remove a user from project
  def remove_collaborator(user)
    project_collaborators.find_by(user: user)&.destroy
  end

  # Check if user has access to project (owner or collaborator)
  def accessible_by?(user)
    owner_id == user.id || project_collaborators.exists?(user: user)
  end

  # Check if user is admin of project (owner only)
  def admin?(user)
    owner_id == user.id
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    # Ensure uniqueness within company
    counter = 1
    while company && Project.exists?(company: company, slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def owner_belongs_to_company
    return unless owner && company
    return if owner.company_id == company_id

    errors.add(:owner, "must belong to the same company as the project")
  end
end
