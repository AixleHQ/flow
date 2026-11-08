# frozen_string_literal: true

module Web
  module Company
    # Company runners (docs/design/agent-runtimes/DESIGN.md §3.2). Every member
    # sees them; only a company admin manages them, because a runner is where a
    # session sends its launching user's agent credential.
    #
    # It authorizes the action only. Which runner a request may touch is the
    # controller's lookup: the company-level runners.
    class RunnersPolicy < ApplicationPolicy
      def index? = membership.present?
      def show? = index?

      def create? = admin?
      def update? = admin?
      def destroy? = admin?
      def disable? = admin?
      def enable? = admin?
      def revoke? = admin?
    end
  end
end
