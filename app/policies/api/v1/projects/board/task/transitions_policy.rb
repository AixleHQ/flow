# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class TransitionsPolicy < Web::Company::Projects::Board::Task::TransitionsPolicy
            def index? = project_accessible?
          end
        end
      end
    end
  end
end
