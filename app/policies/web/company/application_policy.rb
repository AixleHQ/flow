# frozen_string_literal: true

module Web
  module Company
    class ApplicationPolicy < ::ApplicationPolicy
      private

      def current_user
        context.user
      end

      def project
        context.respond_to?(:project) ? context.project : nil
      end

      def project_accessible?
        project&.accessible_by?(current_user)
      end

      def project_writable?
        project_accessible? && !current_user.read_only?
      end
    end
  end
end
