# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class AgentsController < ApplicationController
          def index
            agents = Agent.merged_for_project(current_project)
            respond_with agents, each_serializer: AgentSerializer
          end

          def create
            agent = current_project.agents.create(agent_params)
            respond_with agent
          end

          def update
            agent = current_project.agents.find(params[:id])
            agent.update(agent_params)
            respond_with agent
          end

          def destroy
            agent = current_project.agents.find(params[:id])
            agent.destroy
            respond_with agent
          end

          private

          def agent_params
            params.require(:agent).permit(:name, :title, :icon, :persona, :communication_style, :principles)
          end
        end
      end
    end
  end
end
