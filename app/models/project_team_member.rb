# frozen_string_literal: true

class ProjectTeamMember < ApplicationRecord
  belongs_to :project_team, inverse_of: :memberships
  belongs_to :user
  belongs_to :added_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :project_team_id, message: "is already in this team" }
  validate :user_may_join, on: :create

  delegate :project, to: :project_team

  private

  def user_may_join
    return unless user && project_team

    if user.exclude_from_teams?
      errors.add(:user, "has asked not to be added to teams")
    elsif !WorkflowTriggers::RunAs.eligible_users(project).exists?(id: user.id)
      errors.add(:user, "must be a member of the project who can start runs")
    end
  end
end
