# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        module Task
          class StatisticsPolicy < Web::Company::ApplicationPolicy
            def show? = project_accessible?

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
end
