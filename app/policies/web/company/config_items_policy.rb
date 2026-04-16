# frozen_string_literal: true

module Web
  module Company
    class ConfigItemsPolicy < ApplicationPolicy
      def index? = current_user.admin?
      def create? = current_user.admin?
      def update? = current_user.admin?
      def destroy? = current_user.admin?
    end
  end
end
