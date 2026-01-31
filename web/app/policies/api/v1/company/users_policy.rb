# frozen_string_literal: true

module Api
  module V1
    module Company
      class UsersPolicy < ApplicationPolicy
        def index?
          current_user.admin?
        end

        def create?
          current_user.admin?
        end

        def update?
          current_user.admin? && same_company?
        end

        def destroy?
          current_user.admin? && same_company? && not_self?
        end

        private

        def record
          current_user.company.users.find(context.params[:id])
        end

        def current_user
          context.user
        end

        def same_company?
          record.company_id == current_user.company_id
        end

        def not_self?
          record.id != current_user.id
        end
      end
    end
  end
end
