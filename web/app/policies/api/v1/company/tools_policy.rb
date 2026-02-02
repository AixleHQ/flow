# frozen_string_literal: true

module Api
  module V1
    module Company
      class ToolsPolicy < ApplicationPolicy
        def index?
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
      end
    end
  end
end
