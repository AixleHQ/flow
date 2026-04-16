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

        if workflow.update(workflow_params)
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
        params.require(:workflow).permit(:name, :description, config: {})
      end
    end
  end
end
