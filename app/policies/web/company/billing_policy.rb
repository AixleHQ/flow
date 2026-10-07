# frozen_string_literal: true

module Web
  module Company
    # What the workspace pays is the administrators' business, like the limit
    # that decides it.
    class BillingPolicy < ApplicationPolicy
      def show? = admin?
    end
  end
end
