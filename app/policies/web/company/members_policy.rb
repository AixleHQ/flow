# frozen_string_literal: true

module Web
  module Company
    class MembersPolicy < ApplicationPolicy
      def index?
        true
      end

      def create?
        current_user.admin?
      end

      def update?
        current_user.admin? && same_company? && not_changing_own_role?
      end

      def destroy?
        current_user.admin? && same_company? && not_self?
      end

      private

      def target_user
        current_user.company.users.find(context.params[:id])
      end

      def same_company?
        target_user.company_id == current_user.company_id
      end

      def not_self?
        target_user.id != current_user.id
      end

      def not_changing_own_role?
        return true unless context.params[:user]&.key?(:role)

        target_user.id != current_user.id
      end
    end
  end
end
