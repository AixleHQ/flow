# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class TransitionsController < Task::ApplicationController
            def index
              transitions = current_task.column_transitions.order(created_at: :desc)
              render json: transitions.map { |t| ColumnTransitionResource.new(t).to_h }
            end
          end
        end
      end
    end
  end
end
