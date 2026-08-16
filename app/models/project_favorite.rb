# frozen_string_literal: true

# One person's star on one project. Per-user by construction: the row carries
# the user, so favoriting cannot reorder anybody else's project list.
#
# Access is NOT re-derived here. The lists that read favorites are already
# scoped by `Project.for_user`, so a row for a project the user later loses
# access to simply stops being joined — a favorite can never surface a project
# the user is not allowed to see. What this model does guard is the company
# boundary, matching ProjectCollaborator: a user with no active membership in
# the project's company has no business starring it.
class ProjectFavorite < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :project

  # Validations
  validates :project_id, uniqueness: { scope: :user_id, message: "is already a favorite for this user" }
  validate :user_belongs_to_project_company

  private

  def user_belongs_to_project_company
    return unless user && project
    return if user.company_memberships.active.exists?(company_id: project.company_id)

    errors.add(:user, "must belong to the same company as the project")
  end
end
