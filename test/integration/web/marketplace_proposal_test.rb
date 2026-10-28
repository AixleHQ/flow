# frozen_string_literal: true

require "test_helper"

# A buyer whose domain already has a workspace asking for their subscription to
# be applied to it, and an administrator there answering.
#
# The asking takes two steps on purpose. A typed address proves nothing, and a
# proposal raised on one would be a way to put a request in front of the
# administrators of any domain, from any AWS account.
class Web::MarketplaceProposalTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: true))
    @client = FakeMarketplaceSellerClient.new
    Billing::MarketplaceSellerClient.stubs(:new).returns(@client)
    @company = create(:company, name: "Northwind", email_domain: "northwind.example")
    @admin = create(:user, :admin, :onboarding_completed, company: @company,
                                                          password: AuthHelper::TEST_PASSWORD)
  end

  # The buyer, as the fulfilment URL leaves them: signed out, holding a licence
  # in the session and nothing else.
  def arrive_from_marketplace
    post marketplace_registration_landing_path, params: { "x-amzn-marketplace-token" => "tok" }
    follow_redirect!
    follow_redirect!
  end

  def ask(email: "dana@northwind.example")
    post marketplace_proposal_path, params: { email: email }
  end

  # The HTML part, decoded. The mail is multipart -- the layout carries an
  # inline logo -- so `body` is the multipart envelope and holds no link at all;
  # and `decoded` rather than `to_s` because quoted-printable soft-wraps a long
  # URL in the middle of the token.
  def link_from_mail
    mail = ActionMailer::Base.deliveries.last
    body = (mail.html_part || mail).decoded
    CGI.unescape(body[%r{proposal\?token=([^"&\s]+)}, 1].to_s)
  end

  # -- Asking ----------------------------------------------------------------

  test "asking only sends a link, and raises nothing" do
    arrive_from_marketplace

    assert_emails 1 do
      ask
      perform_enqueued_jobs
    end

    assert_nil MarketplaceLicense.last.proposed_company, "nothing is raised until the address is proved"
    assert_nil MarketplaceLicense.last.proposal_state
  end

  test "opening the link raises the request against the workspace at that domain" do
    arrive_from_marketplace
    ask
    perform_enqueued_jobs

    get confirm_marketplace_proposal_path(token: link_from_mail)

    license = MarketplaceLicense.last
    assert_equal @company, license.proposed_company
    assert_equal "dana@northwind.example", license.proposed_by_email
    assert license.proposal_pending?
  end

  test "every administrator of that workspace is told" do
    other = create(:user, :admin, :onboarding_completed, company: @company)
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    token = link_from_mail
    ActionMailer::Base.deliveries.clear

    get confirm_marketplace_proposal_path(token: token)
    perform_enqueued_jobs

    assert_equal [ @admin.email, other.email ].sort, ActionMailer::Base.deliveries.map { |m| m.to.first }.sort
  end

  # The address the link proved is an administrator's of the very workspace
  # being asked: a workspace that cancelled its subscription and took out a
  # new one. Asking themselves by mail and waiting for their own answer was the
  # long way round; the proof signs them in and puts the request in front of
  # them, and the other administrators are told as before.
  test "an administrator proving their own address lands on the request, signed in" do
    other = create(:user, :admin, :onboarding_completed, company: @company)
    arrive_from_marketplace
    ask(email: @admin.email)
    perform_enqueued_jobs
    token = link_from_mail
    ActionMailer::Base.deliveries.clear

    get confirm_marketplace_proposal_path(token: token)
    perform_enqueued_jobs

    assert_redirected_to company_settings_billing_path
    assert MarketplaceLicense.last.proposal_pending?
    assert_equal [ other.email ], ActionMailer::Base.deliveries.map { |m| m.to.first },
                 "the other administrator is told; the one asking is not"
    follow_redirect!
    assert_inertia_props do |props|
      assert_equal @admin.email, props.dig(:marketplaceProposal, :askedBy)
      assert props.dig(:marketplaceProposal, :canDecide)
    end
  end

  # The link lives two hours and the buyer has it in front of them, so opening
  # it twice is a double click or a returned-to tab. Raising again would mail
  # every administrator a second time -- the one route the rate limit on asking
  # does not cover.
  test "opening the link again is a reload, not a second ask" do
    other = create(:user, :admin, :onboarding_completed, company: @company)
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    token = link_from_mail

    get confirm_marketplace_proposal_path(token: token)
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    get confirm_marketplace_proposal_path(token: token)
    perform_enqueued_jobs

    assert_redirected_to new_workspace_path(email: "dana@northwind.example")
    assert_empty ActionMailer::Base.deliveries, "the administrators were asked once"
    assert_not_nil other
    assert MarketplaceLicense.last.proposal_pending?, "and the request still stands"
  end

  # The link outlives the answer by up to two hours. Opened again after a no,
  # it would raise the same request again and mail every administrator who
  # had just declined it.
  test "a declined request is not raised again from the same link" do
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    token = link_from_mail
    get confirm_marketplace_proposal_path(token: token)
    license = MarketplaceLicense.last
    # The administrator answers from their own browser; the buyer keeps theirs.
    admin = open_session
    admin.post login_path, params: { user: { email: @admin.email, password: AuthHelper::TEST_PASSWORD } }
    admin.delete company_marketplace_license_proposal_path
    assert_equal "declined", license.reload.proposal_state
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    get confirm_marketplace_proposal_path(token: token)
    perform_enqueued_jobs

    follow_redirect!
    assert_inertia_props { |props| assert_match(/declined/i, props.dig(:errors, :base).to_s) }
    assert_equal "declined", license.reload.proposal_state, "and the answer stands"
    assert_empty ActionMailer::Base.deliveries
  end

  # Only the link that asked is spent by the answer. The buyer may have spoken
  # to the administrators since, and asking again with the same address has
  # to work -- the two links differ in nothing but when they were issued.
  test "asking again after a decline raises a new request" do
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    get confirm_marketplace_proposal_path(token: link_from_mail)
    license = MarketplaceLicense.last
    admin = open_session
    admin.post login_path, params: { user: { email: @admin.email, password: AuthHelper::TEST_PASSWORD } }
    travel 1.minute
    admin.delete company_marketplace_license_proposal_path
    assert_equal "declined", license.reload.proposal_state
    perform_enqueued_jobs
    ActionMailer::Base.deliveries.clear

    travel 1.minute
    ask
    perform_enqueued_jobs
    get confirm_marketplace_proposal_path(token: link_from_mail)
    perform_enqueued_jobs

    assert license.reload.proposal_pending?, "a fresh ask, not a reload of the declined one"
    assert_includes ActionMailer::Base.deliveries.map { |m| m.to.first }, @admin.email
  end

  # The address is the whole of the proof, so a link that was tampered with,
  # signed elsewhere, or has simply expired raises nothing.
  #
  # The refusal has to reach the page that draws it. Sent as a flash, which
  # that page draws nowhere, it left a refused buyer on an empty form -- one
  # their claimed domain makes unusable anyway -- with no trace of what they had
  # just done, and nothing sensible left to try but subscribing again.
  test "a token that is not ours raises nothing, and says so where it can be read" do
    get confirm_marketplace_proposal_path(token: "not-a-token")

    follow_redirect!
    assert_inertia_props { |props| assert_match(/expired/i, props.dig(:errors, :base).to_s) }
    assert_equal 0, MarketplaceLicense.where.not(proposal_state: nil).count
  end

  # The address goes back with the refusal, so what renders is the screen that
  # explains the domain rather than a form the person cannot use.
  test "a refusal returns the buyer to the screen that explains their domain" do
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    token = link_from_mail
    create(:marketplace_license, :active, company: @company)

    get confirm_marketplace_proposal_path(token: token)

    follow_redirect!
    assert_inertia_props do |props|
      assert_equal "northwind.example", props.dig(:claimedDomain, :domain)
      assert_match(/already has an AWS Marketplace subscription/, props.dig(:errors, :base).to_s)
    end
  end

  test "a link stops working once it is old" do
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    token = link_from_mail

    travel(MarketplaceProposalTicket::TTL + 1.minute) do
      get confirm_marketplace_proposal_path(token: token)
    end

    assert_nil MarketplaceLicense.last.proposed_company
  end

  # The workspace is looked up from the proved address, never passed in, so
  # there is no parameter here through which to aim a request somewhere else.
  # Told before the inbox, not after it: a buyer sent to open a link that can
  # only be refused has been sent on an errand for nothing.
  test "asking for a domain with no workspace is refused before any mail goes out" do
    arrive_from_marketplace

    ask(email: "dana@nowhere.example")
    perform_enqueued_jobs

    assert_empty ActionMailer::Base.deliveries
    follow_redirect!
    assert_inertia_props { |props| assert_match(/no workspace at that domain/i, props.dig(:errors, :base).to_s) }
  end

  # The domain had a workspace when the link was sent and none when it was
  # opened: the link raises nothing rather than guessing.
  test "a proved address at a domain whose workspace has since gone raises nothing" do
    gone = create(:company, email_domain: "somewhere-else.example")
    arrive_from_marketplace
    ask(email: "dana@somewhere-else.example")
    perform_enqueued_jobs
    gone.destroy!

    get confirm_marketplace_proposal_path(token: link_from_mail)

    assert_redirected_to new_workspace_path(email: "dana@somewhere-else.example")
    assert_nil MarketplaceLicense.last.proposed_company
  end

  test "somebody with no subscription cannot ask at all" do
    assert_emails 0 do
      ask
      perform_enqueued_jobs
    end

    follow_redirect!
    assert_inertia_props { |props| assert_match(/cannot find the subscription/i, props.dig(:errors, :base).to_s) }
  end

  # -- Answering -------------------------------------------------------------

  def raised
    arrive_from_marketplace
    ask
    perform_enqueued_jobs
    get confirm_marketplace_proposal_path(token: link_from_mail)
    MarketplaceLicense.last
  end

  test "an administrator sees the request, with what accepting would do" do
    raised
    sign_in_as(@admin)

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_equal "dana@northwind.example", props.dig(:marketplaceProposal, :askedBy)
      assert_equal MarketplaceLicense.last.customer_aws_account_id,
                   props.dig(:marketplaceProposal, :awsAccountId),
                   "the account that would be billed, and that can end the subscription"
      assert props.dig(:marketplaceProposal, :canDecide)
    end
  end

  test "accepting binds the subscription and moves who bills the workspace" do
    license = raised
    sign_in_as(@admin)

    post company_marketplace_license_proposal_path

    assert_equal @company, license.reload.company
    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, @company.reload.billing_provider
  end

  test "declining leaves the subscription attached to nothing" do
    license = raised
    sign_in_as(@admin)

    delete company_marketplace_license_proposal_path

    assert_nil license.reload.company
    assert_equal "declined", license.proposal_state
    assert_equal Company::BILLING_PROVIDER_NONE, @company.reload.billing_provider
  end

  # Who may move who bills the workspace is who may manage its billing.
  test "somebody who is not an administrator cannot answer" do
    license = raised
    member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)

    post company_marketplace_license_proposal_path

    assert_nil license.reload.company
    assert license.proposal_pending?
  end

  test "the buyer is told either way" do
    raised
    sign_in_as(@admin)
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs { delete company_marketplace_license_proposal_path }

    assert_equal [ "dana@northwind.example" ], ActionMailer::Base.deliveries.map { |m| m.to.first }
  end

  # Hiding the tab made a workspace's billing look missing rather than managed
  # somewhere else. It stays, and says where the bill comes from.
  test "a workspace AWS bills keeps its Billing tab, with no controls on it" do
    raised
    sign_in_as(@admin)
    post company_marketplace_license_proposal_path

    get company_settings_billing_path

    assert_inertia_page "Company/Settings/BillingPage"
    assert_inertia_props do |props|
      assert_equal MarketplaceLicense.last.customer_aws_account_id, props.dig(:marketplaceBilling, :awsAccountId)
      assert_not props.dig(:marketplaceBilling, :ended)
      # Two meanings, two names. `marketplace` is the shared prop the
      # stopped-workspace banner reads; a page prop of that name shadows it and
      # the banner announces an ended subscription to a running workspace.
      assert_nil props[:marketplace], "the banner has nothing to say about a running workspace"
      assert props[:permissions][:canViewBilling], "the tab is offered"
      assert_not props[:permissions][:canManageBilling], "and nothing on it is ours to change"
    end
  end

  test "a workspace nobody AWS-bills has no marketplace panel" do
    sign_in_as(@admin)

    get company_settings_billing_path

    assert_inertia_props { |props| assert_nil props[:marketplaceBilling] }
  end

  test "an answered request cannot be answered twice" do
    license = raised
    sign_in_as(@admin)
    delete company_marketplace_license_proposal_path

    post company_marketplace_license_proposal_path

    assert_nil license.reload.company, "the decline stands"
    assert_match(/no longer waiting/i, flash[:alert])
  end
end
