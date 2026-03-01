# frozen_string_literal: true

module Api
  module V1
    module Company
      class WorkflowsController < ApplicationController
        def index
          workflows = Workflow.visible_for_company(current_company)
                              .includes(:steps, :runs)
                              .ransack(params[:q]).result
          respond_with paginate(workflows), each_serializer: WorkflowSerializer
        end

        def show
          workflow = accessible_workflows.find(params[:id])
          respond_with workflow, serializer: WorkflowSerializer
        end

        def create
          workflow = current_company.workflows.new(workflow_params)
          workflow.save
          respond_with workflow, serializer: WorkflowSerializer
        end

        def update
          workflow = current_company.workflows.active.find(params[:id])
          workflow.update(workflow_params)
          respond_with workflow, serializer: WorkflowSerializer
        end

        def destroy
          workflow = current_company.workflows.active.find(params[:id])
          if workflow.has_active_runs?
            render json: { error: "Cannot delete workflow with active runs. Stop all runs first." }, status: :unprocessable_entity
            return
          end
          workflow.soft_delete!
          head :no_content
        end

        private

        def accessible_workflows
          project_ids = current_company.projects.pluck(:id)
          Workflow.active.where(
            "(scope_type = 'Company' AND scope_id = :company_id) OR (scope_type = 'Project' AND scope_id IN (:project_ids))",
            company_id: current_company.id, project_ids: project_ids.presence || [ 0 ]
          )
        end

        def workflow_params
          params.require(:workflow).permit(:name, :description, config: {})
        end
      end
    end
  end
end
