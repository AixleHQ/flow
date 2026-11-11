# frozen_string_literal: true

module PersonalTools
  class DeleteProjectTeam < Base
    include ProjectTeamSupport

    tool do
      display_name "Delete Project Team"
      description "Delete a team. Board tasks assigned to it become unassigned. Refused while a trigger " \
                  "runs as the team — point those triggers elsewhere first. Company admins and the project " \
                  "owner only. Confirm with the user before calling."
      audience :user
      tags :resources
      destructive
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
      param :team_id, type: :integer, description: "Team id (from list_project_teams).", required: true
    end

    def execute
      project = find_project!
      authorize_manage!(project)
      team = find_team!(project)

      ProjectTeams::Management.new(project: project, actor: user).destroy!(team)
      success(deleted: true, team_id: team.id)
    rescue ProjectTeams::Management::InUse => e
      error(e.message)
    end
  end
end
