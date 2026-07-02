# frozen_string_literal: true

module Api
  module V1
    # Base policy for the api/v1 tree. Exposes the read-only predicate and the
    # project accessibility helpers so non-project-scoped policies can gate on
    # `read_only?` directly, while project-scoped policies inherit the shared
    # classification from their Web::Company::Projects::* counterparts.
    class ApplicationPolicy < ::ApplicationPolicy
      private

      def current_user
        context.user
      end

      # Membership in the context company. Project-scoped API policies get it
      # derived from the project's company (via ProjectContext); company-less
      # API calls have no membership and fall back to the global predicate.
      def membership
        context.membership
      end

      # Per-company viewer when a company context exists. FAIL CLOSED:
      # - company context + no active membership there → read-only (no write);
      # - no company context + zero active memberships → read-only
      #   (viewer_everywhere? is false for an empty set — never rely on it
      #   alone to gate writes). Super admins (no memberships by design) are
      #   exempt from the zero-membership rule.
      def read_only?
        return !!membership.viewer? if membership
        return true if context.company
        return false if current_user.super_admin?

        current_user.active_memberships.none? || current_user.viewer_everywhere?
      end

      def project
        context.respond_to?(:project) ? context.project : nil
      end

      def project_accessible?
        project&.accessible_by?(current_user)
      end

      # Writable = accessible AND not a viewer in that project's company.
      def project_writable?
        project_accessible? && !read_only?
      end
    end
  end
end
