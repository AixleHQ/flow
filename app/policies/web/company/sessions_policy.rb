# frozen_string_literal: true

module Web
  module Company
    class SessionsPolicy < ApplicationPolicy
      def index? = admin?
      def new? = admin?
      def show? = admin?
    end
  end
end
