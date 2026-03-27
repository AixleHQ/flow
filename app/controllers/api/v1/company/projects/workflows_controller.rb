# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class WorkflowsController < ApplicationController
          def index
            workflows = Workflow.visible_for_project(current_project)
                                .includes(:steps, runs: [])
                                .ransack(params[:q]).result
            respond_with paginate(workflows), each_serializer: WorkflowSerializer, project: current_project
          end

          def show
            workflow = Workflow.visible_for_project(current_project).find(params[:id])
            respond_with workflow, serializer: WorkflowSerializer
          end

          def create
            workflow = current_project.workflows.new(workflow_params)
            workflow.save
            respond_with workflow, serializer: WorkflowSerializer
          end

          def duplicate
            source = Workflow.active.find(params[:id])
            duplicator = WorkflowDuplicator.new(source, target_scope: current_project)
            new_workflow = duplicator.duplicate!
            respond_with new_workflow, serializer: WorkflowSerializer, status: :created
          end

          def update
            workflow = current_project.workflows.active.find(params[:id])
            merged = workflow_params.to_h
            if merged[:config].present?
              merged[:config] = (workflow.config || {}).merge(merged[:config].stringify_keys)
            end
            workflow.update(merged)
            respond_with workflow, serializer: WorkflowSerializer
          end

          def destroy
            workflow = current_project.workflows.active.find(params[:id])
            if workflow.has_active_runs?
              render json: { error: "Cannot delete workflow with active runs. Stop all runs first." }, status: :unprocessable_entity
              return
            end
            workflow.soft_delete!
            head :no_content
          end

          private

          def workflow_params
            params.require(:workflow).permit(:name, :description, config: {})
          end
        end
      end
    end
  end
end
