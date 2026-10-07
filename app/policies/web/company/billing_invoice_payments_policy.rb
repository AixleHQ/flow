# frozen_string_literal: true

module Web
  module Company
    class BillingInvoicePaymentsPolicy < ApplicationPolicy
      def create? = admin?
    end
  end
end
