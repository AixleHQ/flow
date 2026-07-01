# frozen_string_literal: true

module Web
  module Company
    module Projects
      class MCPServersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
