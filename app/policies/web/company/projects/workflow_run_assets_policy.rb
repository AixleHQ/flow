# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowRunAssetsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def export? = project_accessible?
        def download? = project_accessible?
        def export_all? = project_accessible?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
