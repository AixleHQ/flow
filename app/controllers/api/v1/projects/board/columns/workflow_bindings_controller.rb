# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Columns
          class WorkflowBindingsController < Board::ApplicationController
            def show
              binding = current_column.column_workflow_binding
              return head(:not_found) unless binding

              render json: ColumnWorkflowBindingResource.new(binding).to_h
            end

            def create
              binding = current_column.build_column_workflow_binding(binding_params)
              binding.save!
              render json: ColumnWorkflowBindingResource.new(binding).to_h, status: :created
            end

            def update
              binding = current_column.column_workflow_binding
              return head(:not_found) unless binding

              binding.update!(binding_params)
              render json: ColumnWorkflowBindingResource.new(binding).to_h
            end

            def destroy
              binding = current_column.column_workflow_binding
              return head(:not_found) unless binding

              binding.destroy!
              head :no_content
            end

            private

            def current_column
              @current_column ||= current_board.board_columns.find(params[:column_id])
            end

            def binding_params
              params.require(:column_workflow_binding).permit(:workflow_id, :trigger_mode, :cooldown_seconds)
            end
          end
        end
      end
    end
  end
end
