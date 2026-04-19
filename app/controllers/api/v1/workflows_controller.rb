# frozen_string_literal: true

module Api
  module V1
    class WorkflowsController < ApplicationController
      def show
        workflow = Workflow.for_company(current_company).find(params[:id])
        render json: WorkflowResource.new(workflow).to_h
      end

      def update
        workflow = Workflow.for_company(current_company).active.find(params[:id])

        if workflow.update(merged_workflow_params(workflow))
          render json: WorkflowResource.new(workflow).to_h
        else
          render json: { errors: workflow.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        workflow = Workflow.for_company(current_company).active.find(params[:id])

        if workflow.has_active_runs?
          render json: { error: "Cannot delete workflow with active runs" }, status: :unprocessable_entity
          return
        end

        workflow.soft_delete!
        head :no_content
      end

      private

      def current_company
        @current_company ||= current_user.company
      end

      def workflow_params
        params.require(:workflow).permit(:name, :description, :inherit_all_project_resources, config: {})
      end

      def merged_workflow_params(workflow)
        permitted = workflow_params
        config_updates = {}
        config_updates["inherit_all_project_resources"] = permitted.delete(:inherit_all_project_resources) if permitted.key?(:inherit_all_project_resources)
        return permitted if config_updates.empty?

        permitted.merge(config: (workflow.config || {}).merge(config_updates))
      end
    end
  end
end
