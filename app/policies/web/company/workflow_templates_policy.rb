# frozen_string_literal: true

module Web
  module Company
    class WorkflowTemplatesPolicy < ApplicationPolicy
      def index? = company_member?
      def show? = company_member?
      def create? = company_member?
      def update? = manage_template?
      def publish_version? = manage_template?

      private

      def company_member?
        current_user.company_id.present?
      end

      def manage_template?
        return false unless company_member?
        return true if current_user.admin?

        template&.owner_id == current_user.id
      end

      def template
        return record if record.is_a?(WorkflowTemplate)

        id = context.params[:id]
        return nil unless id && current_user.company_id

        WorkflowTemplate.find_by(id: id, company_id: current_user.company_id)
      end
    end
  end
end
