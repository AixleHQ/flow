# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class ColumnsPolicy < Web::Company::Projects::Board::ColumnsPolicy
          def index? = project_accessible?
          def show? = project_accessible?
          def create? = project_writable?
          def update? = project_writable?
          def destroy? = project_writable?
          def reorder? = project_writable?
        end
      end
    end
  end
end
