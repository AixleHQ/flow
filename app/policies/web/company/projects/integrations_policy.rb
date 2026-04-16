# frozen_string_literal: true

module Web
  module Company
    module Projects
      class IntegrationsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_accessible? && current_user.admin?
        def destroy? = project_accessible? && current_user.admin?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
