# frozen_string_literal: true

module Api
  module V1
    module Workflows
      class ApplicationController < Api::V1::ApplicationController
        private

        def current_company
          @current_company ||= current_user.company
        end

        def current_workflow
          @current_workflow ||= Workflow.for_company(current_company).active.find(params[:workflow_id])
        end

        def step_params
          params.require(:step).permit(
            :name, :description, :instructions, :position, :agent_id,
            :allow_non_interactive, :skip_policy, :on_failure, :max_retries,
            :mount_repositories, :bmad_enabled, :required_agent_runtime, :preferred_model,
            input_asset_specs: [ :name, :asset_type, :required ],
            output_asset_specs: [ :name, :asset_type, :required, :name_pattern ],
            tool_ids: [], mcp_server_ids: [], skill_ids: [], depends_on_step_ids: [],
            sub_steps_attributes: %i[id position name description instructions required _destroy]
          )
        end
      end
    end
  end
end
