# frozen_string_literal: true

module Api
  module V1
    module Projects
      class AssetsPolicy < Web::Company::Projects::AssetsPolicy
        def download? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
        def bulk_actions? = project_writable?
      end
    end
  end
end
