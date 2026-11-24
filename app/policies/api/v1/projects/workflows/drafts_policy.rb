# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class DraftsPolicy < Web::Company::ApplicationPolicy
          def create? = project_writable?
          def changes? = project_writable?
          def apply? = project_writable?
          def destroy? = project_writable?
        end
      end
    end
  end
end
