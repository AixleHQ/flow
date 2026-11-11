# frozen_string_literal: true

# A named group of a project's members that a board task can be assigned to and
# an off-board trigger can run as. Each run resolves the team to one member
# (ProjectTeams::Picker), so sessions, credentials and the audit trail still belong to
# a person. docs/design/project-teams.md
class ProjectTeam < ApplicationRecord
  extend Enumerize

  STRATEGIES = %w[priority round_robin most_remaining].freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User", optional: true
  has_many :memberships, -> { order(:position, :id) }, class_name: "ProjectTeamMember",
                                                        inverse_of: :project_team, dependent: :delete_all
  has_many :members, through: :memberships, source: :user
  has_many :assigned_tasks, class_name: "BoardTask", foreign_key: :assignee_team_id,
                            inverse_of: :assignee_team, dependent: :nullify
  has_many :trigger_bindings, foreign_key: :run_as_team_id, inverse_of: :run_as_team, dependent: :nullify
  has_many :workflow_runs, foreign_key: :team_id, inverse_of: :team, dependent: :nullify

  enumerize :strategy, in: STRATEGIES, default: :priority, predicates: true

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :project_id }

  def managed_by?(user)
    return false unless user

    membership = user.company_memberships.active.find_by(company_id: project.company_id)
    return false if membership.nil? || membership.viewer?

    membership.admin? || project.owner_id == user.id
  end
end
