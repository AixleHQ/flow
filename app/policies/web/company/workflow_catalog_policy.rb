# frozen_string_literal: true

module Web
  module Company
    class WorkflowCatalogPolicy < ApplicationPolicy
      def index? = company_member?
      def duplicate? = company_member? && !read_only?

      private

      def company_member?
        membership.present?
      end
    end
  end
end
