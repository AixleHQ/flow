# frozen_string_literal: true

module Web
  module Company
    module Projects
      class AssetsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_accessible?
        def destroy? = project_accessible?
        def versions? = project_accessible?
        def download? = project_accessible?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
