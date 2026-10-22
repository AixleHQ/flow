# frozen_string_literal: true

# Where a buyer lands after subscribing to the AWS Marketplace SaaS listing.
#
# Two actions, and the split is forced rather than tidy. AWS sends the buyer's
# browser here with a cross-site form POST carrying `x-amzn-marketplace-token`,
# and a cross-site POST does not carry a `SameSite=Lax` cookie — so the session
# is simply not there to read, whoever is signed in. #create therefore holds no
# session at all: it exchanges the token, writes the licence, and hands the
# licence to #show in a signed token. #show is an ordinary same-site GET on our
# own origin, where the session exists and can be replaced.
#
# What arrives is fixed and cannot be added to: `x-amzn-marketplace-token`
# always, and `x-amzn-marketplace-offer-type` only on a free-trial offer.
# Everything else about the buyer comes back from ResolveCustomer.
class Web::MarketplaceRegistrationsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :verify_authenticity_token, only: :create
  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # The token is the only credential, so the cost of guessing has to be real.
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { request.remote_ip },
             with: -> { refuse("Too many attempts. Try again in an hour.") }

  # AWS sends `x-amzn-marketplace-token` and, on a free-trial offer,
  # `x-amzn-marketplace-offer-type`. ApplicationController#underscore_params puts
  # every incoming key through String#underscore before any action sees it, and
  # that turns hyphens into underscores — so the names AWS documents are not the
  # names this controller can read. Spelling them as AWS does here reads a nil
  # token and registers nobody, silently.
  TOKEN_PARAM = :x_amzn_marketplace_token
  OFFER_TYPE_PARAM = :x_amzn_marketplace_offer_type

  EXPIRED = "That link from AWS Marketplace has expired. Open your subscription " \
            "in AWS Marketplace and choose Set up your account again."
  UNAVAILABLE = "Something went wrong setting your subscription up. We have been told; please try again shortly."

  # POST, from aws.amazon.com.
  def create
    return head :not_found unless registration.configured?

    license = registration.call(
      registration_token: params[TOKEN_PARAM],
      offer_type: params[OFFER_TYPE_PARAM]
    )

    redirect_to marketplace_registration_path(ticket: license.generate_token_for(:registration))
  rescue Billing::MarketplaceSellerClient::InvalidToken, Billing::MarketplaceSellerClient::ForeignProduct
    refuse(EXPIRED)
  rescue Billing::MarketplaceSellerClient::Error => e
    # A role we cannot assume is ours to fix and says nothing useful to a buyer,
    # so it is reported rather than explained.
    Sentry.capture_exception(e)
    refuse(UNAVAILABLE)
  end

  # GET, same-site, carrying the licence the POST resolved.
  def show
    license = MarketplaceLicense.find_by_token_for(:registration, params[:ticket])
    return refuse(EXPIRED) if license.nil?

    # Whoever was signed in here is not necessarily the person who just bought
    # this, and in AWS that button is usually pressed by somebody who will never
    # use the product. Starting from nobody is the only honest default.
    sign_out if signed_in?

    return redirect_to login_path, notice: already_set_up(license) if license.bound?

    session[:marketplace_license_id] = license.id
    redirect_to new_workspace_path
  end

  private

  def registration = @registration ||= Billing::MarketplaceRegistration.new

  def already_set_up(license)
    "This AWS Marketplace subscription already has the workspace " \
      "#{license.company&.name}. Sign in to reach it."
  end

  def refuse(message)
    redirect_to login_path, alert: message
  end
end
