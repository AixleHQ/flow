# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class MCPServersController < ApplicationController
          def index
            servers = MCPServer.visible_for_project(project)
            respond_with servers, each_serializer: MCPServerSerializer, project: project
          end

          def create
            server = project.mcp_servers.create(server_params)
            respond_with server, serializer: MCPServerSerializer
          end

          def update
            server = project_servers.find(params[:id])
            server.update(server_params)
            respond_with server, serializer: MCPServerSerializer
          end

          def destroy
            server = project_servers.find(params[:id])
            server.destroy
            respond_with server
          end

          private

          def project
            @project ||= current_company.projects.find(params[:project_id])
          end

          def project_servers
            MCPServer.for_project(project)
          end

          def server_params
            params.require(:mcp_server).permit(
              :name, :display_name, :url, :transport, :description, :enabled,
              :command, headers: {}, env: {}
            ).merge(kind: :custom)
          end
        end
      end
    end
  end
end
