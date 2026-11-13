# frozen_string_literal: true

module Billing
  # The three ways the admin dashboard tells companies apart for reporting:
  # where the account stands, whether we carry it, and who sends its invoice.
  # Read from the company as it is now, unlike the dashboard's billing class,
  # which is kept per hour.
  class AccountClassification
    # Keyed by Company#billing_status. A subscription set to cancel is still
    # paid for until its period ends.
    STATUS_BY_BILLING_STATUS = {
      "active" => "active_customer",
      "cancelling" => "active_customer",
      "trialing" => "trial_active",
      "allowance" => "trial_expired",
      "canceled" => "canceled",
      "payment_failed" => "locked_nonpayment",
      "awaiting_subscription" => "pending_activation"
    }.freeze

    def self.of(company) = new(company).to_h

    def initialize(company)
      @company = company
    end

    def to_h = { account_status: account_status, account_type: account_type, billing_method: billing_method }

    def account_status
      return "inactive" unless @company.active?

      STATUS_BY_BILLING_STATUS.fetch(@company.billing_status)
    end

    def account_type = @company.managed_by_aixle? ? "managed" : "paid"

    # Nil when nobody invoices the company: one we carry, one that has not paid
    # yet, or any company of a self-hosted installation. `billing_provider` is
    # left as it was when a company becomes ours, so it is not read for one.
    # It also turns to Stripe as soon as card entry is opened, which creates the
    # customer before any card is given, so Stripe takes a subscription as well.
    def billing_method
      return "self_hosted_aws_marketplace" if Deployment.aws_marketplace?
      return if !Deployment.saas? || @company.managed_by_aixle?

      case @company.billing_provider
      when Company::BILLING_PROVIDER_STRIPE then "saas_stripe" if @company.stripe_subscription_id.present?
      when Company::BILLING_PROVIDER_AWS_MARKETPLACE then "saas_aws_marketplace"
      end
    end
  end
end
