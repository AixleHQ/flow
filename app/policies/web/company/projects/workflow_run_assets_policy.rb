# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowRunAssetsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def download? = project_accessible?
        def export? = project_writable?
        def export_all? = project_writable?
      end
    end
  end
end
