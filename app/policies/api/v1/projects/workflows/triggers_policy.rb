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
          def change_run_as? = project_writable? && (membership&.admin? || project.owner_id == current_user.id)
        end
      end
    end
  end
end
