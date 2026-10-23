# frozen_string_literal: true

# Where a buyer lands after subscribing to the AWS Marketplace SaaS listing.
#
# Two actions because a cross-site POST carries no `SameSite=Lax` cookie: the
# request AWS makes has no session to read, whoever is signed in. #create holds
# none, and hands the licence to #show in a signed token; #show is same-site on
# our own origin, where the session exists and can be replaced.
class Web::MarketplaceRegistrationsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :verify_authenticity_token, only: :create
  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # The token is the only credential here.
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

  # GET on the fulfilment URL, which is not how a buyer arrives: AWS posts them
  # here. It exists because AWS fetches the URL before accepting it and refuses
  # anything that is not a 200, and because a kept link lands here.
  def landing
    render inertia: "Marketplace/LandingPage"
  end

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
    # Ours to fix, and nothing a buyer can act on.
    Sentry.capture_exception(e)
    refuse(UNAVAILABLE)
  end

  # GET, same-site, carrying the licence the POST resolved.
  def show
    license = MarketplaceLicense.find_by_token_for(:registration, params[:ticket])
    return refuse(EXPIRED) if license.nil?

    # In AWS the subscribe button is usually pressed by somebody who will never
    # open the product, so whoever is signed in here is not evidence of anything.
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
