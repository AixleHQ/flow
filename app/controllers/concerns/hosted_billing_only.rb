# frozen_string_literal: true

# Billing through Stripe exists only where we host. A self-hosted operator pays
# nobody and a Marketplace customer pays AWS, so there every billing screen and
# action is refused here — not left to fail later on a missing Stripe key or a
# missing subscription.
module HostedBillingOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_hosted_billing!
  end

  private

  def require_hosted_billing!
    return if Deployment.saas?

    redirect_to company_settings_path, alert: "Billing is not available on this installation."
  end
end
