# frozen_string_literal: true

module Web
  module Company
    class IntegrationsPolicy < ApplicationPolicy
      def index? = current_user.admin?
      def github_setup? = current_user.admin?
      def create? = current_user.admin?
      def destroy? = current_user.admin?
    end
  end
end
