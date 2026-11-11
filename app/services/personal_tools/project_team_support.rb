# frozen_string_literal: true

module PersonalTools
  # Shared by the project-team tools (docs/design/project-teams.md).
  module ProjectTeamSupport
    STRATEGIES = ProjectTeam::STRATEGIES
    STRATEGY_DESCRIPTION = "How a run picks the member it goes to: priority (the first member in the " \
                           "team's order who can take it), round_robin (the next member after the one " \
                           "picked last), most_remaining (the member with the most agent quota left)."

    private

    def find_team!(project)
      team = project.project_teams.find_by(id: params[:team_id])
      raise Base::NotFoundError, "Team #{params[:team_id]} not found in project #{project.id}" unless team

      team
    end

    def authorize_manage!(project)
      authorize!(project, :manage?, policy: Web::Company::Projects::TeamsPolicy, project: project)
    end

    def serialize_team(team, context: nil)
      ProjectTeamResource.new(team, params: { snake_keys: true, context: context }.compact).to_h
    end
  end
end
