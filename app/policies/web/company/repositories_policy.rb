# frozen_string_literal: true

module Web
  module Company
    class RepositoriesPolicy < ApplicationPolicy
      def index? = true
      def create? = current_user.admin?
      def update? = current_user.admin?
      def destroy? = current_user.admin?
      def branches? = current_user.admin?
    end
  end
end
