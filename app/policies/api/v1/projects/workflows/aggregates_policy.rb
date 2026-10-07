# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class AggregatesPolicy < Web::Company::ApplicationPolicy
          def update? = project_writable?
          # A POST, so the API's read-only backstop refuses viewers anyway; they
          # cannot edit the workflow the check is about.
          def check? = project_writable?
        end
      end
    end
  end
end
