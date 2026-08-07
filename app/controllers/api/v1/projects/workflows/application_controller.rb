# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class ApplicationController < Api::V1::Projects::ApplicationController
          private

          def current_workflow
            @current_workflow ||= current_project.workflows.active.find(params[:workflow_id])
          end

          def step_params
            params.require(:step).permit(
              :name, :instructions, :position, :agent_id,
              :allow_non_interactive, :skip_policy, :on_failure, :max_retries,
              :bmad_enabled, :required_agent_runtime, :preferred_model,
              input_asset_specs: [ :name, :asset_type, :required ],
              output_asset_specs: [ :name, :asset_type, :required, :name_pattern ],
              tool_ids: [], mcp_server_ids: [], skill_ids: [], asset_ids: [], repository_ids: [],
              depends_on_step_ids: [],
              sub_steps_attributes: %i[id position name instructions required _destroy]
            )
          end
        end
      end
    end
  end
end
