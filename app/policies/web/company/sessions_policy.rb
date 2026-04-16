# frozen_string_literal: true

module Web
  module Company
    class SessionsPolicy < ApplicationPolicy
      def index? = true
      def new? = true
      def show? = true
    end
  end
end
