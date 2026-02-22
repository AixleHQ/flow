# frozen_string_literal: true

module Api
  module V1
    module Company
      module Workflows
        class StepsPolicy < Api::V1::Company::ApplicationPolicy
          def index?
            current_user.admin?
          end

          def show?
            current_user.admin?
          end

          def create?
            current_user.admin?
          end

          def update?
            current_user.admin?
          end

          def destroy?
            current_user.admin?
          end

          def reorder?
            current_user.admin?
          end
        end
      end
    end
  end
end
