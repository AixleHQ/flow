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
            run = current_project.workflow_runs.new(workflow_run_params.merge(user: current_user, workflow: workflow))

            validate_mode!(run, workflow)
            return respond_with run if run.errors.any?

            if run.save
              workflow.steps.order(:position).each do |step|
                run.step_runs.find_or_create_by!(step: step)
              end
              start_temporal_workflow(run)
              respond_with run, serializer: WorkflowRunSerializer, status: :created
            else
              respond_with run
            end
          end

          def approve_step
            run = current_project.workflow_runs.find(params[:id])
            current_step = run.current_step_run
            return head(:not_found) unless current_step

            current_step.mark_completed!
            send_workflow_signal(run, "step_completed")
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def retry_step
            run = current_project.workflow_runs.find(params[:id])
            current_step = run.current_step_run
            return head(:not_found) unless current_step

            current_step.mark_failed!("Retried by user")
            send_workflow_signal(run, "step_retried")
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def skip_step
            run = current_project.workflow_runs.find(params[:id])
            current_step = run.current_step_run
            return head(:not_found) unless current_step

            reason = params[:reason] || "Skipped by user"
            current_step.mark_skipped!(reason)
            send_workflow_signal(run, "step_skipped")
            respond_with run.reload, serializer: WorkflowRunSerializer
          end

          def cancel
            run = current_project.workflow_runs.find(params[:id])
            send_workflow_signal(run, "workflow_cancelled")

            run.cancel! if run.may_cancel?
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

          def validate_mode!(run, workflow)
            return unless run.non_interactive?

            overrides = run.step_overrides || {}
            blocking_steps = workflow.steps.reject do |step|
              override = overrides[step.id.to_s]
              override ? override["auto_run"] : step.allow_non_interactive
            end

            return if blocking_steps.empty?

            names = blocking_steps.map(&:name)
            run.errors.add(:mode, "Cannot run fully automatic: steps #{names.join(', ')} require user interaction")
          end

          def start_temporal_workflow(run)
            WorkflowService.start_workflow_execution(run)
          rescue StandardError => e
            Rails.logger.error("Failed to start Temporal workflow for WorkflowRun##{run.id}: #{e.message}")
          end

          def send_workflow_signal(run, signal_name)
            TemporalService.send_signal("workflow-execution-#{run.id}", signal_name)
          rescue StandardError => e
            Rails.logger.error("Failed to send signal #{signal_name} for WorkflowRun##{run.id}: #{e.message}")
          end
        end
      end
    end
  end
end
