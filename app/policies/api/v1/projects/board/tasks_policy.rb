# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class TasksPolicy < Web::Company::Projects::Board::TasksPolicy
          def index? = project_accessible?
          def show? = project_accessible?
          def workflow_runs? = project_accessible?
          def create? = project_writable?
          def update? = project_writable?
          def destroy? = project_writable?
          def move? = project_writable?
          def archive? = project_writable?
          def unarchive? = project_writable?
          def trigger_workflow? = project_writable?
        end
      end
    end
  end
end
