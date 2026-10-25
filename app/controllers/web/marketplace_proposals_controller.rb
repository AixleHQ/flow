# frozen_string_literal: true

# A buyer asking the administrators of the workspace at their domain to apply
# the subscription they have just bought.
#
# Reached only by somebody the fulfilment URL signed out, holding a licence in
# the session and nothing else. The address they give is unproved until the link
# this sends is opened, which is the whole reason the asking takes two steps —
# see MarketplaceProposalTicket.
class Web::MarketplaceProposalsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # Mail to an address of somebody's choosing, so the same gun the signup form
  # is behind. Inert in test, where the cache is a null store.
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { request.remote_ip },
             with: -> { refuse("Too many attempts. Try again in an hour.") }

  EXPIRED = "That link has expired. Open the page AWS Marketplace sent you to and ask again."
  NO_SUBSCRIPTION = "We cannot find the subscription that request was for."

  def create
    return refuse(NO_SUBSCRIPTION) unless license&.proposable?
    return refuse("Enter the work email address you will use Aixle Flow with.") unless address.present?

    MarketplaceProposalMailer.confirm(
      email: address, token: MarketplaceProposalTicket.issue(license_id: license.id, email: address)
    ).deliver_later

    redirect_to new_workspace_path(email: address, asked: "check-email")
  end

  # The link. Opening it is the proof, so this is where the request is actually
  # raised and where the administrators are told.
  def confirm
    answers = MarketplaceProposalTicket.decode(params[:token])
    return refuse(EXPIRED) if answers.nil?

    proposed = MarketplaceLicense.find_by(id: answers[:license_id])
    return refuse(NO_SUBSCRIPTION) if proposed.nil?

    raise_proposal(proposed, answers[:email])
  rescue Billing::MarketplaceLicenseProposal::Refused => e
    refuse(e.message)
  end

  private

  def raise_proposal(proposed, email)
    Billing::MarketplaceLicenseProposal.raise!(license: proposed, email: email)
    notify_admins(proposed.reload)

    # No marker in the URL: the licence itself now says a request is waiting, so
    # the screen reads the same whether this is the redirect or a reload of it
    # an hour later.
    redirect_to new_workspace_path(email: email)
  end

  # Every administrator, because there is no billing contact and the decision
  # moves who pays for their workspace.
  def notify_admins(proposed)
    proposed.proposed_company.billing_admins.find_each do |admin|
      MarketplaceProposalMailer.raised(proposed, admin).deliver_later
    end
  end

  def license
    return @license if defined?(@license)

    @license = MarketplaceLicense.find_by(id: session[:marketplace_license_id])
  end

  def address
    @address ||= begin
      typed = params[:email].to_s.strip.downcase
      typed.match?(URI::MailTo::EMAIL_REGEXP) ? typed : nil
    end
  end

  def refuse(message)
    redirect_to new_workspace_path, alert: message
  end
end
