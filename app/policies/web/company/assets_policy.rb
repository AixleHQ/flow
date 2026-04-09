# frozen_string_literal: true

module Web
  module Company
    class AssetsPolicy < ApplicationPolicy
      def index? = current_user.admin?
      def create? = current_user.admin?
      def destroy? = current_user.admin?
      def versions? = current_user.admin?
      def download? = current_user.admin?
    end
  end
end
