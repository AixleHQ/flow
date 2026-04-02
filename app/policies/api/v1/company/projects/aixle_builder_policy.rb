# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class AixleBuilderPolicy < Api::V1::Company::ApplicationPolicy
          def start?
            project_accessible?
          end

          def status?
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
