# frozen_string_literal: true

module Web
  module Company
    module Projects
      class RepositoriesPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_writable? && admin?
        def update? = project_writable? && admin?
        def destroy? = project_writable? && admin?
      end
    end
  end
end
