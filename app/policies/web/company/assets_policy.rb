# frozen_string_literal: true

module Web
  module Company
    class AssetsPolicy < ApplicationPolicy
      def index? = admin?
      def create? = admin?
      def destroy? = admin?
      def versions? = admin?
      def download? = admin?
    end
  end
end
