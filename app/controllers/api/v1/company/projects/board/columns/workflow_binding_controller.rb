# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Columns
            class WorkflowBindingController < Api::V1::Company::Projects::ApplicationController
              def show
                binding = current_column.column_workflow_binding
                return head(:not_found) unless binding

                respond_with binding, serializer: ColumnWorkflowBindingSerializer
              end

              def create
                binding = current_column.build_column_workflow_binding(binding_params)
                binding.save
                respond_with binding, serializer: ColumnWorkflowBindingSerializer
              end

              def update
                binding = current_column.column_workflow_binding
                return head(:not_found) unless binding

                binding.update(binding_params)
                respond_with binding, serializer: ColumnWorkflowBindingSerializer
              end

              def destroy
                binding = current_column.column_workflow_binding
                return head(:not_found) unless binding

                binding.destroy!
                head :no_content
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

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
end
