# frozen_string_literal: true

module Api
  module V1
    module Company
      class RepositoriesPolicy < ApplicationPolicy
        def index?
          true
        end

        def show?
          true
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

        def available?
          current_user.admin?
        end

        def branches?
          current_user.admin?
        end

      end
    end
  end
end
