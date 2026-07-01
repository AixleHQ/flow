# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def builder? = project_accessible?
        def show? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
        def publish? = project_writable?
        def unpublish? = project_writable?
        def duplicate? = project_writable?
      end
    end
  end
end
