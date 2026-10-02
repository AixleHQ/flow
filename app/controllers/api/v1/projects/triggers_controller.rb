# frozen_string_literal: true

module Api
  module V1
    module Projects
      # Every trigger of the project's live workflows, for the project's Triggers
      # page. Writes stay on the workflow's own triggers endpoint, which the
      # page addresses through each trigger's workflow_id.
      class TriggersController < ApplicationController
        def index
          # The workflows whose triggers this project can edit (the per-workflow endpoint's).
          workflows = current_project.workflows.active
          bindings = TriggerBinding.where(project_id: current_project.id, workflow: workflows)
                                   .includes(:created_by, :workflow).order(:created_at).to_a
          columns = ColumnWorkflowBinding.joins(board_column: :board).where(boards: { project_id: current_project.id })
                                         .where(workflow: workflows).includes(:board_column, :created_by, :workflow)
                                         .order(:created_at)
          serializer = WorkflowTriggers::Serializer.new(webhook_endpoints: WorkflowTriggers::Serializer.endpoints_for(bindings))

          render json: { triggers: columns.map { |b| serializer.column(b) } + bindings.map { |b| serializer.binding(b) } }
        end
      end
    end
  end
end
