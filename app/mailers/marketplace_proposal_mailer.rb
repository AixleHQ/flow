# frozen_string_literal: true

# Asking for an AWS Marketplace subscription to be applied to a workspace that
# already exists: proving the asker's address, and putting the question to the
# people who can answer it.
class MarketplaceProposalMailer < ApplicationMailer
  # To the buyer. Until this is opened nothing has been raised and nobody has
  # been told, because the address it goes to is the only thing that ties the
  # asker to the domain they are asking about.
  def confirm(email:, token:)
    @url = marketplace_proposal_link_url(token: token)
    @ttl_hours = (MarketplaceProposalTicket::TTL / 3600).to_i

    mail(to: email, subject: "Confirm your request to apply an AWS Marketplace subscription")
  end

  # To each administrator of the workspace being asked about.
  def raised(license, admin)
    @admin = admin
    @company = license.proposed_company
    @asked_by = license.proposed_by_email
    @aws_account_id = license.customer_aws_account_id
    @card_billed = @company.stripe_subscription_id.present?
    @url = company_settings_billing_url

    mail(to: admin.email, subject: "A request to bill #{@company.name} through AWS Marketplace")
  end

  # To the buyer, once somebody has answered.
  def decided(license)
    @company = license.proposed_company
    @accepted = license.proposal_state == "accepted"

    mail(to: license.proposed_by_email,
         subject: @accepted ? "Your AWS Marketplace subscription is set up" : "Your request was not accepted")
  end
end
