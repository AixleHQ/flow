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

      def read_only?
        current_user.read_only?
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
