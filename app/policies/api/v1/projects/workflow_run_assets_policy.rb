# frozen_string_literal: true

module Api
  module V1
    module Projects
      class WorkflowRunAssetsPolicy < Web::Company::Projects::WorkflowRunAssetsPolicy
        def index? = project_accessible?
        def download? = project_accessible?
        def export? = project_writable?
        def export_all? = project_writable?
      end
    end
  end
end
