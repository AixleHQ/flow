# frozen_string_literal: true

module Web
  module Company
    class SessionsPolicy < ApplicationPolicy
      def index? = current_user.admin?
      def new? = current_user.admin?
      def show? = current_user.admin?
    end
  end
end
