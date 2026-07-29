# frozen_string_literal: true

module Web
  module Company
    class MembersPolicy < ApplicationPolicy
      def index?
        true
      end

      def create?
        admin?
      end

      def resend?
        admin? && same_company?
      end

      def update?
        admin? && same_company? && not_changing_own_role?
      end

      def destroy?
        admin? && same_company? && not_self?
      end

      private

      # Deliberately raising (`find_by!`, not `find_by`): a foreign admin passes
      # admin?, so `&&` does not short-circuit and this scoped lookup misses
      # this company's member, raising RecordNotFound — which
      # show_exceptions=:rescuable turns into a 404. Non-admins never reach here
      # because `admin? &&` short-circuits first, so they get a plain policy
      # denial (302 + alert). That split is the response contract pinned by
      # AuthorizationMatrix#assert_company_admin_only.
      def target_membership
        @target_membership ||= context.company.company_memberships.find_by!(user_id: context.params[:id])
      end

      def same_company?
        target_membership.present?
      end

      def not_self?
        context.params[:id].to_s != current_user.id.to_s
      end

      def not_changing_own_role?
        return true unless context.params[:user]&.key?(:role)

        not_self?
      end
    end
  end
end
