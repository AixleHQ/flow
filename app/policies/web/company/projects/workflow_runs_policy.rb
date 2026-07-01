# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowRunsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = project_accessible?
        def create? = project_writable?
        def cancel? = project_writable?
        def approve_step? = project_writable?
        def retry_step? = project_writable?
        def skip_step? = project_writable?
      end
    end
  end
end
