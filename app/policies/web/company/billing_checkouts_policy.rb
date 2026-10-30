# frozen_string_literal: true

module Web
  module Company
    # Anyone in the workspace who can change anything may add the card that
    # keeps it running; what it costs, and cancelling, stay the administrators'.
    class BillingCheckoutsPolicy < ApplicationPolicy
      def create? = !read_only?
    end
  end
end
