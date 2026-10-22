# frozen_string_literal: true

require "test_helper"

# The fulfilment URL, from the browser's side.
#
# The POST is what AWS makes: cross-site, form encoded, no CSRF token and — this
# is the part that shapes the controller — no session cookie, because
# SameSite=Lax withholds one from a cross-site POST. So nothing here signs
# anybody in or out; that is the GET's job, on our own origin.
class Web::MarketplaceRegistrationTest < ActionDispatch::IntegrationTest
  setup do
    @client = FakeMarketplaceSellerClient.new
    Billing::MarketplaceSellerClient.stubs(:new).returns(@client)
  end

  # Spelled as AWS spells it, on purpose: the controller has to survive
  # underscore_params turning these hyphens into underscores.
  def register(token: "tok", offer_type: nil)
    params = { "x-amzn-marketplace-token" => token }
    params["x-amzn-marketplace-offer-type"] = offer_type if offer_type

    post marketplace_registration_landing_path, params: params
  end

  def ticket_from_redirect
    Rack::Utils.parse_query(URI.parse(response.location).query)["ticket"]
  end

  test "a buyer arriving from AWS gets a licence and a ticket to carry it" do
    assert_difference -> { MarketplaceLicense.count }, 1 do
      register
    end

    assert_response :redirect
    license = MarketplaceLicense.last
    assert_equal "tok", @client.last_token
    assert_equal license, MarketplaceLicense.find_by_token_for(:registration, ticket_from_redirect)
  end

  test "the POST needs no CSRF token, which is the whole reason it is skipped" do
    ActionController::Base.allow_forgery_protection = true
    register

    assert_response :redirect
    assert_equal 1, MarketplaceLicense.count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a free-trial arrival records what it said, without deciding what it means" do
    register(offer_type: "free-trial")

    assert_equal "free-trial", MarketplaceLicense.last.registered_offer_type
  end

  test "an installation that does not sell the listing answers nothing at all" do
    @client.configured = false
    register

    assert_response :not_found
    assert_equal 0, MarketplaceLicense.count
  end

  test "an expired link sends the buyer back to AWS rather than into a stack trace" do
    @client.failure = Billing::MarketplaceSellerClient::InvalidToken
    register

    assert_redirected_to login_path
    assert_match(/expired/i, flash[:alert])
    assert_match(/AWS Marketplace/, flash[:alert])
  end

  test "a role we cannot assume is reported to us and not explained to the buyer" do
    @client.failure = Billing::MarketplaceSellerClient::CredentialsError
    register

    assert_redirected_to login_path
    assert_no_match(/role|assume|arn/i, flash[:alert])
  end

  test "following the ticket lands an unknown visitor on workspace creation" do
    register
    follow_redirect!

    assert_redirected_to new_workspace_path
    assert_equal MarketplaceLicense.last.id, session[:marketplace_license_id]
  end

  # In AWS the subscribe button is usually pressed by procurement or a cloud
  # administrator. Whoever is signed in on this browser is not evidence of who
  # just bought the subscription.
  test "whoever was signed in is signed out before anything is bound" do
    user = create(:user, :admin, :onboarding_completed,
                  company: create(:company), password: AuthHelper::TEST_PASSWORD)
    sign_in_as(user)
    assert session[:user_id].present?, "the precondition: somebody really is signed in on this browser"

    register
    follow_redirect!

    assert_nil session[:user_id]
    assert_redirected_to new_workspace_path
  end

  test "a licence already bound sends the buyer to sign in, naming the workspace" do
    company = create(:company, name: "Procurement Ltd")
    register
    MarketplaceLicense.last.update!(company: company, subscription_state: "active")

    follow_redirect!

    assert_redirected_to login_path
    assert_match(/Procurement Ltd/, flash[:notice])
    assert_nil session[:marketplace_license_id]
  end

  test "a ticket that is not ours, or no longer valid, is refused" do
    get marketplace_registration_path(ticket: "not-a-ticket")

    assert_redirected_to login_path
    assert_match(/expired/i, flash[:alert])
    assert_nil session[:marketplace_license_id]
  end

  test "a ticket stops working once it is old" do
    register
    ticket = ticket_from_redirect

    travel(MarketplaceLicense::REGISTRATION_VALID_FOR + 1.minute) do
      get marketplace_registration_path(ticket: ticket)

      assert_redirected_to login_path
      assert_match(/expired/i, flash[:alert])
    end
  end
end
