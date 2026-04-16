# frozen_string_literal: true

class Web::Company::Projects::AgentsController < Web::Company::Projects::ApplicationController
  def index
    agents = Agent.visible_for_project(current_project).order(created_at: :desc)

    render inertia: "Projects/Agents/AgentsPage", props: {
      project: project_props,
      agents: agents.map { |a| AgentResource.new(a).to_h }
    }
  end

  def create
    agent = current_project.agents.new(agent_params)

    if agent.save
      redirect_to company_project_agents_path(current_project), notice: "Agent created"
    else
      redirect_to company_project_agents_path(current_project), inertia: { errors: agent.errors }
    end
  end

  def update
    agent = current_project.agents.find(params[:id])

    if agent.update(agent_params)
      redirect_to company_project_agents_path(current_project), notice: "Agent updated"
    else
      redirect_to company_project_agents_path(current_project), inertia: { errors: agent.errors }
    end
  end

  def destroy
    agent = current_project.agents.find(params[:id])
    agent.destroy
    redirect_to company_project_agents_path(current_project), notice: "Agent deleted"
  end

  private

  def agent_params
    params.require(:agent).permit(:name, :title, :icon, :persona, :communication_style, :principles)
  end
end
