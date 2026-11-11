# frozen_string_literal: true

module PersonalTools
  class ListProjectTeams < Base
    include ProjectTeamSupport

    tool do
      display_name "List Project Teams"
      description "List a project's teams: named groups of members a board task can be assigned to " \
                  "(assignee_team_id) and an off-board trigger can run as (run_as_team_id). Each run of a " \
                  "team goes to one member, picked by the team's strategy. Shows each member's connected " \
                  "runtimes and any quota hold that keeps them out of picks."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::TeamsPolicy, project: project)

      teams = project.project_teams.includes(memberships: :user).to_a
      context = ProjectTeamResource.context_for(teams)
      success(project_id: project.id, teams: teams.map { |team| serialize_team(team, context: context) })
    end
  end
end
