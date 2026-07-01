# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class CommentsPolicy < Web::Company::Projects::Board::Task::CommentsPolicy
            def index? = project_accessible?
            def create? = project_writable?
          end
        end
      end
    end
  end
end
