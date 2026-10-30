# frozen_string_literal: true

module Web
  module Company
    # Like adding a card: whoever can change anything may pay what stopped the
    # workspace.
    class BillingInvoicePaymentsPolicy < ApplicationPolicy
      def create? = !read_only?
    end
  end
end
