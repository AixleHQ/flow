# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class AggregatesPolicy < Web::Company::ApplicationPolicy
          def update? = project_writable?
        end
      end
    end
  end
end
