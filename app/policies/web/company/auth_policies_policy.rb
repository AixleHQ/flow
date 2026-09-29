# frozen_string_literal: true

module Web
  module Company
    # Admin-only, including the read. Which methods a workspace accepts is a map
    # of its doors: it tells anyone who can see it which one to go at, and it is
    # not information an ordinary member needs.
    class AuthPoliciesPolicy < ApplicationPolicy
      def index? = admin?
      def update? = admin?
    end
  end
end
