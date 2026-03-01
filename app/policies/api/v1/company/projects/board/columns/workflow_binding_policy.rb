# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Columns
            class WorkflowBindingPolicy < Api::V1::Company::ApplicationPolicy
              def show?
                project_accessible?
              end

              def create?
                project_admin?
              end

              def update?
                project_admin?
              end

              def destroy?
                project_admin?
              end

              private

              def project
                context.project
              end

              def project_accessible?
                return false unless project

                project.accessible_by?(current_user)
              end

              def project_admin?
                return false unless project

                project.admin?(current_user)
              end
            end
          end
        end
      end
    end
  end
end
