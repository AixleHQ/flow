# frozen_string_literal: true

module Web
  module Company
    module Projects
      class AixleBuilderPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def start? = project_accessible?
        def show_session? = project_accessible?
        def finish? = project_accessible?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
