# frozen_string_literal: true

class Web::Company::Projects::TeamsController < Web::Company::Projects::ApplicationController
  def index
    teams = current_project.project_teams.includes(memberships: :user).to_a
    context = ProjectTeamResource.context_for(teams)

    render inertia: "Projects/Teams/TeamsPage", props: {
      teams: teams.map { |team| ProjectTeamResource.new(team, params: { context: context }).to_h },
      candidates: candidates,
      can_manage: policy(policy_method_params).manage?
    }
  end

  def create
    team = management.create!(**team_params)
    redirect_to company_project_teams_path(current_project), notice: "Team #{team.name} created"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_teams_path(current_project), inertia: { errors: errors_of(e) }
  end

  def update
    team = management.update!(current_team, **team_params)
    redirect_to company_project_teams_path(current_project), notice: "Team #{team.name} saved"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_teams_path(current_project), inertia: { errors: errors_of(e) }
  end

  def destroy
    team = current_team
    management.destroy!(team)
    redirect_to company_project_teams_path(current_project), notice: "Team #{team.name} deleted"
  rescue ProjectTeams::Management::InUse => e
    redirect_to company_project_teams_path(current_project), alert: e.message
  end

  def leave
    team = current_team
    ProjectTeams::Management.leave!(team, current_user)
    redirect_back fallback_location: company_project_teams_path(current_project), notice: "You left team #{team.name}"
  end

  private

  def current_team
    current_project.project_teams.find(params[:id])
  end

  def management
    ProjectTeams::Management.new(project: current_project, actor: current_user)
  end

  def team_params
    permitted = params.require(:team).permit(:name, :strategy, member_ids: [])
    { name: permitted[:name], strategy: permitted[:strategy], member_ids: permitted[:member_ids] }
      .tap { |attrs| attrs[:member_ids] ||= [] if action_name == "create" }
  end

  # Who may be put in a team: the members the Runs as picker offers. Members
  # without an agent are listed so the page can say why they can't take runs yet.
  def candidates
    excluded = User.where(id: WorkflowTriggers::RunAs.eligible_users(current_project).select(:id))
                   .where(exclude_from_teams: true).pluck(:id).to_set
    WorkflowTriggers::RunAs.candidates(current_project).map do |candidate|
      candidate.merge(excluded_from_teams: excluded.include?(candidate[:id]))
    end
  end

  def errors_of(error)
    { base: error.record.errors.full_messages.to_sentence }
  end
end
