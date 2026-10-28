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
  DECLINED = "The administrators of that workspace declined this request."

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
    return refuse(NO_SUBSCRIPTION, email: answers[:email]) if proposed.nil?
    # Opening the link again inside its two hours is a reload, not a second
    # ask: raising again would replace a request already waiting and mail every
    # administrator a second time, which the rate limit on #create does not
    # cover.
    return redirect_to(new_workspace_path(email: answers[:email])) if already_asked?(proposed, answers[:email])
    # Answered, and the link that asked still inside its two hours: not an ask
    # to raise again, which would put the same question back in front of the
    # administrators who have just said no. A link issued after the answer is
    # a new ask, and goes through.
    return refuse(DECLINED, email: answers[:email]) if already_declined?(proposed, answers)

    raise_proposal(proposed, answers[:email])
  rescue Billing::MarketplaceLicenseProposal::Refused => e
    refuse(e.message, email: answers&.dig(:email))
  end

  private

  # Matched on the address too: a different one is a different ask, and a
  # second proposal replaces a pending one.
  def already_asked?(proposed, email)
    proposed.proposal_pending? && proposed.proposed_by_email == email.to_s.downcase
  end

  def already_declined?(proposed, answers)
    return false unless proposed.proposal_state == "declined"
    return false unless proposed.proposed_by_email == answers[:email].to_s.downcase

    answers[:issued_at].nil? || answers[:issued_at] <= proposed.proposal_decided_at
  end

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

  # The address goes back with it, so the person lands on the screen that
  # explains their domain rather than on a form they cannot use -- and the
  # reason travels as an error, because that screen draws errors and the flash
  # it used to carry was drawn nowhere. A buyer who saw neither was left on an
  # empty form with no trace of what they had just done.
  def refuse(message, email: nil)
    redirect_to new_workspace_path(email: email || address),
                inertia: { errors: { base: message } }
  end
end
