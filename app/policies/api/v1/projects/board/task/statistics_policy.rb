# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class StatisticsPolicy < Web::Company::Projects::Board::Task::StatisticsPolicy
            def show? = project_accessible?
          end
        end
      end
    end
  end
end
