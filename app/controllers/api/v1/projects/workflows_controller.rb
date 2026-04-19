# frozen_string_literal: true

module Api
  module V1
    module Projects
      class WorkflowsController < ApplicationController
        def show
          workflow = Workflow.visible_for_project(current_project).find(params[:id])
          render json: WorkflowResource.new(workflow).to_h
        end

        def update
          workflow = current_project.workflows.active.find(params[:id])

          if workflow.update(merged_workflow_params(workflow))
            render json: WorkflowResource.new(workflow).to_h
          else
            render json: { errors: workflow.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          workflow = current_project.workflows.active.find(params[:id])

          if workflow.has_active_runs?
            render json: { error: "Cannot delete workflow with active runs" }, status: :unprocessable_entity
            return
          end

          workflow.soft_delete!
          head :no_content
        end

        private

        def workflow_params
          params.require(:workflow).permit(:name, :description, :inherit_all_project_resources, config: {})
        end

        def merged_workflow_params(workflow)
          permitted = workflow_params
          config_updates = {}
          if permitted.key?(:inherit_all_project_resources)
            raw = permitted.delete(:inherit_all_project_resources)
            config_updates["inherit_all_project_resources"] = ActiveModel::Type::Boolean.new.cast(raw)
          end
          return permitted if config_updates.empty?

          permitted.merge(config: (workflow.config || {}).merge(config_updates))
        end
      end
    end
  end
end
