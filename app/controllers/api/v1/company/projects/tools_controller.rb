# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class ToolsController < ApplicationController
          def index
            tools = Tool.visible_for_project(current_project).includes(:tool_files)
            respond_with tools, each_serializer: ToolSerializer, project: current_project
          end

          def create
            tool = current_project.tools.new(tool_params)
            tool.save
            respond_with tool, serializer: ToolSerializer
          end

          def update
            tool = current_project.tools.find(params[:id])
            tool.update(tool_params)
            respond_with tool, serializer: ToolSerializer
          end

          def destroy
            tool = current_project.tools.find(params[:id])
            tool.destroy
            respond_with tool
          end

          private

          def tool_params
            params.require(:tool).permit(
              :name, :display_name, :description, :docker_image, :command, :enabled,
              required_config_items: [],
              input_schema: {},
              tool_files_attributes: %i[id path content file _destroy]
            ).merge(scope_type: "Project")
          end
        end
      end
    end
  end
end
