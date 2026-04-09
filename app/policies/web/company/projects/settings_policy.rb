# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SettingsPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def update? = project_accessible?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
