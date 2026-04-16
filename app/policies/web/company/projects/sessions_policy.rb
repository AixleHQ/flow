# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SessionsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def new? = project_accessible?
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
