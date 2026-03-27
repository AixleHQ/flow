# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class PaladBuilderController < ApplicationController
          # POST /api/v1/company/projects/:project_id/palad_builder/start
          def start
            builder_workflow = Workflow.palad_builder

            run = WorkflowService.start(
              workflow: builder_workflow,
              project: current_project,
              user: current_user,
              mode: :interactive
            )

            if run.persisted?
              respond_with run, serializer: WorkflowRunSerializer, status: :created
            else
              respond_with run
            end
          end

          # GET /api/v1/company/projects/:project_id/palad_builder/status
          def status
            runs = current_project.workflow_runs
                                  .joins(:workflow)
                                  .where(workflows: { scope_type: "System", name: "Palad Builder" })
                                  .order(created_at: :desc)

            respond_with paginate(runs), each_serializer: WorkflowRunSerializer
          end
        end
      end
    end
  end
end
