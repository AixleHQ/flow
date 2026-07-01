# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Columns
          class WorkflowBindingsPolicy < Api::V1::ApplicationPolicy
            def show? = project_accessible?
            def create? = project_writable?
            def update? = project_writable?
            def destroy? = project_writable?
          end
        end
      end
    end
  end
end
