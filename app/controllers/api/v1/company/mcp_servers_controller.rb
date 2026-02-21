# frozen_string_literal: true

module Api
  module V1
    module Company
      class MCPServersController < ApplicationController
        def index
          servers = MCPServer.merged_for_company(current_company)
          respond_with servers, each_serializer: MCPServerSerializer
        end

        def create
          server = current_company.mcp_servers.create(server_params)
          respond_with server, serializer: MCPServerSerializer
        end

        def update
          server = MCPServer.for_company(current_company).find(params[:id])
          server.update(server_params)
          respond_with server, serializer: MCPServerSerializer
        end

        def destroy
          server = MCPServer.for_company(current_company).find(params[:id])
          server.destroy
          respond_with server
        end

        private

        def server_params
          params.require(:mcp_server).permit(
            :name, :display_name, :url, :transport, :description, :enabled,
            headers: {}
          ).merge(kind: :custom)
        end
      end
    end
  end
end
