# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        class ActivitiesPolicy < Web::Company::ApplicationPolicy
          def index? = project_accessible?

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
