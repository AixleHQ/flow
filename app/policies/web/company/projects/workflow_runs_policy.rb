# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowRunsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = project_accessible?
        def create? = project_accessible?
        def cancel? = project_accessible?
        def approve_step? = project_accessible?
        def retry_step? = project_accessible?
        def skip_step? = project_accessible?

        private

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
