# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class IntegrationsPolicy < Api::V1::Company::ApplicationPolicy
          def index?
            project_accessible?
          end

          def create?
            project_accessible?
          end

          def destroy?
            project_accessible?
          end

          private

          def project
            context.project
          end

          def project_accessible?
            return false unless project

            project.accessible_by?(current_user)
          end
        end
      end
    end
  end
end
