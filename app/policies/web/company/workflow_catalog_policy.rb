# frozen_string_literal: true

module Web
  module Company
    class WorkflowCatalogPolicy < ApplicationPolicy
      def index? = company_member?
      def duplicate? = company_member?

      private

      def company_member?
        current_user.company_id.present?
      end
    end
  end
end
