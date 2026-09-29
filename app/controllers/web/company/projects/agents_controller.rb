# frozen_string_literal: true

class Web::Company::Projects::AgentsController < Web::Company::Projects::ApplicationController
  def index
    agents = Agent.visible_for_project(current_project).order(created_at: :desc)
    archived = Agent.for_project(current_project).archived.order(archived_at: :desc)

    render inertia: "Projects/Agents/AgentsPage", props: {
      project: project_props,
      agents: agents.map { |a| AgentResource.new(a).to_h },
      archived_agents: archived.map { |a| AgentResource.new(a).to_h }
    }
  end

  def create
    agent = current_project.agents.new(agent_params)
    Versions.save!(agent, actor: version_actor) { agent.save! }
    redirect_to company_project_agents_path(current_project), notice: "Agent created"
  rescue ActiveRecord::RecordInvalid
    redirect_to company_project_agents_path(current_project), inertia: { errors: agent.errors }
  end

  def update
    agent = current_project.agents.unarchived.find(params[:id])
    Versions.save!(agent, actor: version_actor, base_version: params[:base_version]) { agent.update!(agent_params) }
    redirect_to company_project_agents_path(current_project), notice: "Agent updated"
  rescue ActiveRecord::RecordInvalid
    redirect_to company_project_agents_path(current_project), inertia: { errors: agent.errors }
  end

  def destroy
    agent = current_project.agents.unarchived.find(params[:id])
    Versions.archive!(agent, actor: version_actor)
    redirect_to company_project_agents_path(current_project), notice: "Agent archived"
  end

  private

  def agent_params
    params.require(:agent).permit(:name, :title, :icon, :persona, :communication_style, :principles)
  end
end
