# frozen_string_literal: true

module Web
  module Company
    class ApplicationPolicy < ::ApplicationPolicy
      private

      def current_user
        context.user
      end

      # Active membership in the context company (current company for
      # company-scoped screens, the project's company for project screens).
      def membership
        context.membership
      end

      # Per-company admin (platform super_admins never reach company policies).
      def admin?
        membership&.admin? || false
      end

      # Fail closed: no active membership in this company reads as read-only.
      def read_only?
        membership.nil? || !!membership.viewer?
      end

      def project
        context.respond_to?(:project) ? context.project : nil
      end

      def project_accessible?
        project&.accessible_by?(current_user)
      end

      def project_writable?
        project_accessible? && !read_only?
      end
    end
  end
end
