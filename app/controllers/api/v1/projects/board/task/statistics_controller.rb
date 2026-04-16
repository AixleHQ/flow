# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class StatisticsController < Task::ApplicationController
            def show
              result = TaskStatisticsService.new(task: current_task).call
              render json: TaskStatisticsResource.new(result).to_h
            end
          end
        end
      end
    end
  end
end
