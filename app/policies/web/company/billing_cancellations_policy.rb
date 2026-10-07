# frozen_string_literal: true

module Web
  module Company
    class BillingCancellationsPolicy < ApplicationPolicy
      def create? = admin?
      def destroy? = admin?
    end
  end
end
