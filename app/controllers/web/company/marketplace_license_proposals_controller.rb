# frozen_string_literal: true

# An administrator answering a request to bill this workspace through AWS
# Marketplace instead of however it is billed now.
#
# Not under HostedBillingOnly, unlike the rest of the billing screens. The
# workspace being asked about is by definition not yet billed by AWS, so the
# guard would pass on the way in — but accepting is precisely what makes it
# AWS-billed, and the redirect afterwards has to go somewhere the admin can
# still open.
class Web::Company::MarketplaceLicenseProposalsController < Web::Company::ApplicationController
  before_action :require_proposal!

  GONE = "That request is no longer waiting for an answer."

  def create
    Billing::MarketplaceLicenseProposal.new(@license).accept!(by: current_user)
    MarketplaceProposalMailer.decided(@license.reload).deliver_later

    redirect_to company_settings_path,
                notice: "#{current_company.name} is now billed through AWS Marketplace."
  rescue Billing::MarketplaceLicenseProposal::Refused => e
    refuse(e.message)
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[MarketplaceLicenseProposals] company #{current_company.id}: #{e.message}")
    refuse("We could not reach our payment provider. Nothing has changed — try again in a moment.")
  end

  def destroy
    Billing::MarketplaceLicenseProposal.new(@license).decline!(by: current_user)
    MarketplaceProposalMailer.decided(@license.reload).deliver_later

    redirect_to company_settings_billing_path, notice: "The request was declined."
  rescue Billing::MarketplaceLicenseProposal::Refused => e
    refuse(e.message)
  end

  private

  def require_proposal!
    @license = Billing::MarketplaceLicenseProposal.pending_for(current_company)
    redirect_to company_settings_billing_path, alert: GONE if @license.nil?
  end

  def refuse(message)
    redirect_to company_settings_billing_path, alert: message
  end
end
