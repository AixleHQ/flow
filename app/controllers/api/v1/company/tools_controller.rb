# frozen_string_literal: true

module Api
  module V1
    module Company
      class ToolsController < ApplicationController
        def index
          tools = Tool.merged_for_company(current_company)
          respond_with tools, each_serializer: ToolSerializer
        end

        def create
          tool = current_company.tools.new(tool_params)
          tool.save
          respond_with tool, serializer: ToolSerializer
        end

        def update
          tool = current_company.tools.find(params[:id])
          tool.update(tool_params)
          respond_with tool, serializer: ToolSerializer
        end

        def destroy
          tool = current_company.tools.find(params[:id])
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
          )
        end
      end
    end
  end
end
