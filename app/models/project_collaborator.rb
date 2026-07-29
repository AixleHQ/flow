# frozen_string_literal: true

class ProjectCollaborator < ApplicationRecord
  # Associations
  belongs_to :project
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: { scope: :project_id, message: "is already a collaborator on this project" }
  validate :user_belongs_to_same_company
  validate :user_is_not_owner

  private

  def user_belongs_to_same_company
    return unless user && project
    return if user.company_memberships.active.exists?(company_id: project.company_id)

    errors.add(:user, "must belong to the same company as the project")
  end

  def user_is_not_owner
    return unless user && project
    return if project.owner_id != user.id

    errors.add(:user, "cannot be a collaborator on their own project")
  end
end
