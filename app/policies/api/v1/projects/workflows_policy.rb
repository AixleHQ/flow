# frozen_string_literal: true

module Api
  module V1
    module Projects
      class WorkflowsPolicy < Web::Company::Projects::WorkflowsPolicy
        def show? = project_accessible?
        def update? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
