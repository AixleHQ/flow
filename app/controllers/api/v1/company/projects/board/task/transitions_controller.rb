# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class TransitionsController < Api::V1::Company::Projects::ApplicationController
              def index
                transitions = current_task.column_transitions.order(created_at: :desc)
                respond_with transitions, each_serializer: ColumnTransitionSerializer
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end
            end
          end
        end
      end
    end
  end
end
