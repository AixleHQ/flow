# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class AssetsPolicy < Web::Company::Projects::Board::Task::AssetsPolicy
            def index? = project_accessible?
            def create? = project_writable?
            def destroy? = project_writable?
          end
        end
      end
    end
  end
end
