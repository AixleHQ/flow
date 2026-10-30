# frozen_string_literal: true

require "test_helper"

# The second half of the fulfilment flow: a buyer AWS sent us, turning into a
# workspace bound to their subscription.
#
# The email round trip is kept rather than skipped. The AWS subscription proves
# the person bought the product; it proves nothing about the address they type
# here, and claiming a domain takes it from everyone else at it.
class Web::MarketplaceWorkspaceSignupTest < ActionDispatch::IntegrationTest
  setup do
    @client = FakeMarketplaceSellerClient.new
    Billing::MarketplaceSellerClient.stubs(:new).returns(@client)
  end

  def arrive_from_marketplace
    post marketplace_registration_landing_path, params: { "x-amzn-marketplace-token" => "tok" }
    follow_redirect!
    MarketplaceLicense.last
  end

  def fill_in_the_form(email: "buyer@acme-marketplace.test", name: "Acme")
    post workspace_path, params: { workspace: { name: name, email: email } }
  end

  # .decoded because the body is quoted-printable, and the query is parsed rather
  # than captured: the token is URL-encoded in the href, and handing those
  # escapes back to a path helper would encode them a second time.
  def emailed_token
    mail = ActionMailer::Base.deliveries.last
    body = (mail.html_part || mail).body.decoded
    url = body[%r{https?://[^"'\s<]*/workspace/confirm\?[^"'\s<]+}]

    Rack::Utils.parse_query(URI.parse(url).query).fetch("token")
  end

  test "the form is reachable even where a stranger may not sign up" do
    Deployment.stubs(:self_serve_signup?).returns(false)
    arrive_from_marketplace

    get new_workspace_path

    assert_response :success
  end

  # AWS bills from the first minute, so a page that promises free trial days is
  # promising something nobody can deliver.
  test "a Marketplace buyer is not offered a free trial on the form" do
    arrive_from_marketplace

    get new_workspace_path

    assert_inertia_page "Workspaces/NewPage"
    assert_inertia_props { |props| assert_nil props[:trialDays] }
  end

  test "an ordinary visitor still sees the trial" do
    Deployment.stubs(:self_serve_signup?).returns(true)

    get new_workspace_path

    assert_inertia_props { |props| assert_equal Billing::Trial.days, props[:trialDays] }
  end

  test "without a licence that door stays shut" do
    Deployment.stubs(:self_serve_signup?).returns(false)

    get new_workspace_path

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "the workspace a buyer confirms is bound to their licence and billed by AWS" do
    license = arrive_from_marketplace

    perform_enqueued_jobs do
      assert_difference -> { Company.count }, 0, "nothing is written before the address is proved" do
        fill_in_the_form
      end
    end

    assert_difference -> { Company.count }, 1 do
      get confirm_workspace_path(token: emailed_token)
    end

    company = Company.last
    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, company.billing_provider
    assert company.billing_payer.aws_marketplace?
    assert_equal license.reload.company, company
  end

  # AWS discards metering for an agreement it has not confirmed, so a workspace
  # that ran in that window would be free to its buyer and costly to us. What
  # decides it is the agreement's own status, asked at registration -- not the
  # arrival, which proves only that somebody pressed a button.
  test "a workspace waits while AWS has not confirmed the agreement" do
    @client.agreement_status = "AWAITING_ACCEPTANCE"
    arrive_from_marketplace

    perform_enqueued_jobs { fill_in_the_form }
    get confirm_workspace_path(token: emailed_token)

    company = Company.last
    assert company.billing_blocked?
    assert_equal "awaiting_subscription", company.billing_block_reason
    assert_equal "awaiting_subscription", company.billing_status
  end

  # The usual case, and the one the first real subscription got wrong: by the
  # time the buyer fills this in, the agreement is live and asking says so. A
  # workspace created blocked here had nothing to unblock it.
  test "a workspace whose agreement is already live starts at once" do
    arrive_from_marketplace

    perform_enqueued_jobs { fill_in_the_form }
    get confirm_workspace_path(token: emailed_token)

    company = Company.last
    assert company.billing_active?
    assert_nil company.billing_block_reason
  end

  test "a Marketplace workspace is never put on our own free allowance" do
    arrive_from_marketplace

    perform_enqueued_jobs { fill_in_the_form }
    get confirm_workspace_path(token: emailed_token)

    assert_not Company.last.billing_trialing?
    assert_not Billing::Trial.applies?(Company.last)
  end

  # The link may be opened anywhere, so the licence cannot live only in the
  # session that started the signup.
  test "the licence survives the link being opened in another browser" do
    license = arrive_from_marketplace
    perform_enqueued_jobs { fill_in_the_form }
    token = emailed_token

    reset!

    get confirm_workspace_path(token: token)

    assert_equal Company.last, license.reload.company
    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, Company.last.billing_provider
  end

  test "a licence already bound cannot be claimed by a second signup" do
    license = arrive_from_marketplace
    perform_enqueued_jobs { fill_in_the_form }
    token = emailed_token
    license.update!(company: create(:company))

    assert_no_difference -> { Company.count } do
      get confirm_workspace_path(token: token)
    end

    assert_redirected_to new_workspace_path
    assert_match(/already has a workspace/i, Array(session[:inertia_errors][:base]).join(" "))
  end

  test "an ordinary signup is untouched by any of this" do
    Deployment.stubs(:self_serve_signup?).returns(true)

    perform_enqueued_jobs { fill_in_the_form(email: "someone@ordinary-signup.test") }
    get confirm_workspace_path(token: emailed_token)

    company = Company.last
    assert_equal Company::BILLING_PROVIDER_NONE, company.billing_provider
    assert company.billing_trialing?
    assert_nil company.marketplace_license
  end
end
