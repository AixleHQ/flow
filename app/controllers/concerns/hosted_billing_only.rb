# frozen_string_literal: true

# Billing through Stripe exists only where we host. A self-hosted operator pays
# nobody and a Marketplace customer pays AWS, so there every billing screen and
# action is refused here — not left to fail later on a missing Stripe key or a
# missing subscription. A company we carry (`managed_by_aixle`) pays nobody
# either, and a card added through Checkout would bill it anyway.
module HostedBillingOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_hosted_billing!
  end

  private

  def require_hosted_billing!
    unless Deployment.saas?
      return redirect_to company_settings_path, alert: "Billing is not available on this installation."
    end
    return unless current_company.managed_by_aixle?

    redirect_to company_settings_path, alert: "This workspace is managed by Aixle and is not billed."
  end
end
