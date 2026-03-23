# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class WorkflowRunsController < ApplicationController
          def index
            runs = current_project.workflow_runs.includes(:workflow, step_runs: :step).order(created_at: :desc)
            respond_with paginate(runs), each_serializer: WorkflowRunSerializer
          end

          def show
            run = current_project.workflow_runs.find(params[:id])
            respond_with run, serializer: WorkflowRunSerializer
          end

          def create
            workflow = accessible_workflows.find(workflow_run_params[:workflow_id])

            run = WorkflowService.start(
              workflow: workflow,
              project: current_project,
              user: current_user,
              mode: workflow_run_params[:mode]&.to_sym || :interactive,
              overrides: workflow_run_params[:step_overrides] || {},
              input_asset_ids: workflow_run_params[:input_asset_ids] || [],
              repository_ids: workflow_run_params[:repository_ids] || [],
              agent_runtime: workflow_run_params[:agent_runtime]
            )

            if run.persisted?
              respond_with run, serializer: WorkflowRunSerializer, status: :created
            else
              respond_with run
            end
          end

          def approve_step
            run = current_project.workflow_runs.find(params[:id])
            current_step = run.current_step_run
            return head(:not_found) unless current_step

            WorkflowService.approve_step(step_run: current_step)
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def retry_step
            run = current_project.workflow_runs.find(params[:id])
            step_run = run.current_step_run || run.latest_failed_step_run
            return head(:not_found) unless step_run&.retryable?

            WorkflowService.retry_step(step_run: step_run)
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def skip_step
            run = current_project.workflow_runs.find(params[:id])
            current_step = run.current_step_run
            return head(:not_found) unless current_step

            WorkflowService.skip_step(step_run: current_step, reason: params[:reason])
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def cancel
            run = current_project.workflow_runs.find(params[:id])
            WorkflowService.cancel(run: run)
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          private

          def workflow_run_params
            permitted = params.require(:workflow_run).permit(:workflow_id, :mode, :agent_runtime, input_asset_ids: [], repository_ids: [])
            permitted[:step_overrides] = params[:workflow_run][:step_overrides]&.to_unsafe_h || {}
            permitted
          end

          def accessible_workflows
            Workflow.visible_for_project(current_project)
          end
        end
      end
    end
  end
end
