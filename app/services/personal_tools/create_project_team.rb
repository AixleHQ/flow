# frozen_string_literal: true

module PersonalTools
  class CreateProjectTeam < Base
    include ProjectTeamSupport

    tool do
      display_name "Create Project Team"
      description "Create a team in a project. Its runs spend its members' own agent subscriptions, so " \
                  "only company admins and the project owner may create one, and every member added is " \
                  "told by email. Members must be project members who can start runs (list_project_members)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
      param :name, type: :string, description: "Team name, unique in the project.", required: true
      param :strategy, type: :string, enum: ProjectTeamSupport::STRATEGIES,
                       description: "#{ProjectTeamSupport::STRATEGY_DESCRIPTION} Defaults to priority."
      param :member_ids, type: :array, items: { type: "integer" },
                         description: "User ids of the members, in the team's order."
    end

    def execute
      project = find_project!
      authorize_manage!(project)

      team = ProjectTeams::Management.new(project: project, actor: user)
                                     .create!(name: params[:name], strategy: params[:strategy],
                                              member_ids: Array(params[:member_ids]))
      success(serialize_team(team))
    rescue ActiveRecord::RecordInvalid => e
      error(e.record.errors.full_messages.join(", "))
    rescue ActiveRecord::RecordNotFound
      error("A member id does not name a user who can join this team")
    end
  end
end
