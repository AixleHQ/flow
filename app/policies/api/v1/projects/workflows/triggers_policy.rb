# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Workflows
        class TriggersPolicy < Api::V1::ApplicationPolicy
          def index? = project_accessible?
          def create? = project_writable?
          def update? = project_writable?
          def destroy? = project_writable?
        end
      end
    end
  end
end
