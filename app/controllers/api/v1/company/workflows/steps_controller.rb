# frozen_string_literal: true

module Api
  module V1
    module Company
      module Workflows
        class StepsController < ApplicationController
          def index
            steps = current_workflow.steps.includes(:sub_steps)
            respond_with steps, each_serializer: StepSerializer
          end

          def show
            step = current_workflow.steps.find(params[:id])
            respond_with step, serializer: StepSerializer
          end

          def create
            step = current_workflow.steps.new(step_params)
            step.save
            respond_with step, serializer: StepSerializer
          end

          def update
            step = current_workflow.steps.find(params[:id])
            step.update(step_params)
            respond_with step, serializer: StepSerializer
          end

          def destroy
            step = current_workflow.steps.find(params[:id])
            step.destroy
            respond_with step
          end

          def reorder
            positions = params.require(:positions).permit!.to_h
            ActiveRecord::Base.transaction do
              current_workflow.steps.update_all("position = position + 10000")
              positions.each do |step_id, new_position|
                current_workflow.steps.unscoped.find(step_id).update_column(:position, new_position.to_i)
              end
            end
            head :ok
          end

          private

          def current_workflow
            @current_workflow ||= current_company.workflows.active.find(params[:workflow_id])
          end

          def step_params
            params.require(:step).permit(
              :name, :description, :instructions, :position, :agent_id,
              :allow_non_interactive, :skip_policy, :on_failure, :max_retries,
              :mount_repositories,
              input_asset_specs: [ :name, :asset_type, :required ],
              output_asset_specs: [ :name, :asset_type, :required, :name_pattern ],
              tool_ids: [],
              mcp_server_ids: [],
              skill_ids: [],
              depends_on_step_ids: [],
              sub_steps_attributes: %i[id position name description instructions required _destroy]
            )
          end
        end
      end
    end
  end
end
