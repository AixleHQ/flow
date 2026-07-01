# frozen_string_literal: true

module Web
  module Company
    module Projects
      class AssetsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def versions? = project_accessible?
        def download? = project_accessible?
        def create? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
