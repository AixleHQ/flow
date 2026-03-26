# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class StatisticsController < Api::V1::Company::Projects::ApplicationController
              # GET /api/v1/company/projects/:project_id/board/tasks/:task_id/statistics
              def show
                result = TaskStatisticsService.new(task: current_task).call

                render json: TaskStatisticsSerializer.new(result).as_json
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
