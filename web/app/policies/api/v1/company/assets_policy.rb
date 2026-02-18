# frozen_string_literal: true

module Api
  module V1
    module Company
      class AssetsPolicy < ApplicationPolicy
        def index?
          current_user.admin?
        end

        def show?
          current_user.admin?
        end

        def versions?
          current_user.admin?
        end

        def download?
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

        def restore?
          current_user.admin?
        end
      end
    end
  end
end
