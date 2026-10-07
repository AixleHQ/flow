# frozen_string_literal: true

# The Billing tab of company settings: where the subscription stands, what this
# period has cost so far, and the controls that change it.
class Web::Company::BillingController < Web::Company::ApplicationController
  before_action :require_hosted_billing!

  def show
    render inertia: "Company/Settings/BillingPage", props: {
      company: { name: current_company.name },
      billing: Billing::Overview.new(current_company).to_h,
      # Where Checkout sent the admin back from. Only these two values, so the
      # page never echoes an arbitrary query string.
      checkout_result: params[:billing].presence_in(%w[done cancelled])
    }
  end

  private

  # A self-hosted operator pays nobody and a Marketplace customer pays AWS.
  def require_hosted_billing!
    redirect_to company_settings_path unless Deployment.saas?
  end
end
