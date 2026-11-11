# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Aixle Insights (docs/design/insights-usage-export.md §5). The connection serves the
      # whole company, so a company admin makes, rotates and removes it; a project's switches
      # and mapping are its owner's or admin's, as are the Insights projects it can map to.
      class InsightsPolicy < Web::Company::ApplicationPolicy
        def connect? = company_admin?
        def rotate? = company_admin?
        def disconnect? = company_admin?
        def update? = manage_project?
        def projects? = manage_project?

        private

        def company_admin?
          admin? && project_accessible?
        end

        def manage_project?
          project_writable? && (admin? || project.admin?(current_user))
        end
      end
    end
  end
end
