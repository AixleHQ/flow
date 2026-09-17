# frozen_string_literal: true

module Web
  module Company
    # Every member may see which methods their company accepts; only an admin
    # may change them.
    class AuthPoliciesPolicy < ApplicationPolicy
      def index?
        true
      end

      def update?
        admin?
      end
    end
  end
end
