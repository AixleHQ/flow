# frozen_string_literal: true

module Web
  module Company
    # Paying for the workspace is an administrator's act, like setting the limit
    # that decides what it costs.
    class BillingCheckoutsPolicy < ApplicationPolicy
      def create? = admin?
    end
  end
end
