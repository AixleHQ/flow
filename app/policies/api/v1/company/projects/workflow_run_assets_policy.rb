# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class WorkflowRunAssetsPolicy < ApplicationPolicy
          def index?
            project_accessible?
          end

          def export?
            project_accessible?
          end

          def export_all?
            project_accessible?
          end
        end
      end
    end
  end
end
