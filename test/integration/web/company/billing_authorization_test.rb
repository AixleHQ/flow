# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the billing tab and its controls.
#
# Policies: Web::Company::{Billing,BillingCancellations,BillingInvoicePayments}Policy
#   every action => admin?
#
# Unscoped, like settings#update: a foreign admin acts on THEIR own company, so
# both companies are paying and Stripe answers for both.
class Web::Company::BillingAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  ADMINS_ONLY_READ = { admin: :allowed_read, foreign_admin: :allowed_read,
                       owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied }.freeze
  ADMINS_ONLY_WRITE = { admin: :allowed_write, foreign_admin: :allowed_write,
                        owner: :denied, collaborator: :denied, viewer: :denied, stranger: :denied }.freeze

  setup do
    setup_company_authz_personas
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    [ @company, @foreign_company ].each do |company|
      company.update!(stripe_customer_id: "cus_#{company.id}", stripe_subscription_id: "sub_#{company.id}",
                      billing_period_starts_at: 10.days.ago, billing_period_ends_at: 20.days.from_now)
      @client.add_subscription(id: company.stripe_subscription_id)
    end
  end

  teardown { teardown_authz }

  test "the billing tab is for admins" do
    assert_role_matrix(ADMINS_ONLY_READ, transport: :web) { get company_settings_billing_path }
  end

  test "cancelling is for admins" do
    assert_role_matrix(ADMINS_ONLY_WRITE, transport: :web) { post company_billing_cancellation_path }
  end

  test "resuming is for admins" do
    assert_role_matrix(ADMINS_ONLY_WRITE, transport: :web) { delete company_billing_cancellation_path }
  end

  test "paying the open invoice is for admins" do
    [ @company, @foreign_company ].each do |company|
      company.update!(billing_state: "blocked", billing_block_reason: "payment_failed",
                      billing_unpaid_invoice_url: "https://invoice.stripe.test/#{company.id}")
    end

    # 409 + X-Inertia-Location for the allowed: the invoice is on Stripe's domain.
    assert_role_matrix(ADMINS_ONLY_WRITE, transport: :web, allowed_status: :conflict) do
      post company_billing_invoice_payment_path
    end
  end
end
