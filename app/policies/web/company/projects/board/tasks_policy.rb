# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        class TasksPolicy < Web::Company::ApplicationPolicy
          def index? = project_accessible?
          def show? = project_accessible?
          def create? = project_accessible?
          def update? = project_accessible?
          def destroy? = project_accessible?
          def move? = project_accessible?
          def workflow_runs? = project_accessible?
          def trigger_workflow? = project_accessible?

          private

          def project = context.project

          def project_accessible?
            project&.accessible_by?(current_user)
          end
        end
      end
    end
  end
end
