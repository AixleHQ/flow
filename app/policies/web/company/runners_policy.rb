# frozen_string_literal: true

module Web
  module Company
    # Company runners (docs/design/agent-runtimes/DESIGN.md §3.2). Every member
    # sees them; only a company admin manages them, because a runner is where a
    # session sends its launching user's agent credential.
    class RunnersPolicy < ApplicationPolicy
      def index? = membership.present?
      def show? = index?

      def create? = manage?
      def update? = manage?
      def destroy? = manage?
      def disable? = manage?
      def enable? = manage?
      def revoke? = manage?

      private

      # The record is the runner when the controller has one, and the `:runners`
      # symbol when Pundit authorizes the action before the lookup.
      def manage?
        admin? && (!record.is_a?(Runner) || (record.company_id == context.company&.id && record.project_id.nil?))
      end
    end
  end
end
