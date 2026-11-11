# frozen_string_literal: true

module PersonalTools
  class UpdateProjectTeam < Base
    include ProjectTeamSupport

    tool do
      display_name "Update Project Team"
      description "Rename a team, change its strategy, or replace its member list. member_ids REPLACES " \
                  "the whole list and sets the order — read the team with list_project_teams first. Members " \
                  "added or taken out are told by email. Company admins and the project owner only."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
      param :team_id, type: :integer, description: "Team id (from list_project_teams).", required: true
      param :name, type: :string, description: "New team name."
      param :strategy, type: :string, enum: ProjectTeamSupport::STRATEGIES,
                       description: ProjectTeamSupport::STRATEGY_DESCRIPTION
      param :member_ids, type: :array, items: { type: "integer" },
                         description: "User ids of every member, in the team's order. Replaces the list."
    end

    def execute
      project = find_project!
      authorize_manage!(project)
      team = find_team!(project)

      member_ids = params.key?(:member_ids) ? Array(params[:member_ids]) : nil
      ProjectTeams::Management.new(project: project, actor: user)
                              .update!(team, name: params[:name], strategy: params[:strategy], member_ids: member_ids)
      success(serialize_team(team.reload))
    rescue ActiveRecord::RecordInvalid => e
      error(e.record.errors.full_messages.join(", "))
    rescue ActiveRecord::RecordNotFound
      error("A member id does not name a user who can join this team")
    end
  end
end
