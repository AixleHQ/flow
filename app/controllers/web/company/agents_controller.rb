# frozen_string_literal: true

class Web::Company::AgentsController < Web::Company::ApplicationController
  def index
    agents = Agent.for_company(current_company).order(created_at: :desc)

    render inertia: "Company/Agents/Index", props: {
      agents: agents.map { |a| AgentResource.new(a).to_h }
    }
  end

  def create
    agent = current_company.agents.new(agent_params)

    if agent.save
      redirect_to company_agents_path, notice: "Agent created"
    else
      redirect_to company_agents_path, inertia: { errors: agent.errors }
    end
  end

  def update
    agent = current_company.agents.find(params[:id])

    if agent.update(agent_params)
      redirect_to company_agents_path, notice: "Agent updated"
    else
      redirect_to company_agents_path, inertia: { errors: agent.errors }
    end
  end

  def destroy
    agent = current_company.agents.find(params[:id])
    agent.destroy
    redirect_to company_agents_path, notice: "Agent deleted"
  end

  private

  def agent_params
    params.require(:agent).permit(:name, :title, :icon, :persona, :communication_style, :principles)
  end
end
