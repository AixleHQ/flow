# frozen_string_literal: true

module Web
  module Company
    class MembershipsPolicy < ApplicationPolicy
      # Self-only: a user may leave (revoke) their OWN membership, in any of
      # their companies. Removing other members is MembersPolicy territory.
      def destroy?
        target_membership.present? && target_membership.user_id == current_user.id
      end

      private

      def target_membership
        @target_membership ||= CompanyMembership.find_by(id: context.params[:id])
      end
    end
  end
end
