# frozen_string_literal: true

require "test_helper"

class Web::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { with_mode(Deployment::SAAS) }

  # Registration is off by default, so a suite about signing up says so rather
  # than inheriting whatever the environment left in the settings file.
  def with_mode(mode, registration: true)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: registration))
  end

  def valid_params(**over)
    { workspace: { name: "Acme Robotics", email: "dana@acme-robotics.example", max_sessions: "5" }.merge(over) }
  end

  def ticket(**over)
    WorkspaceSignupTicket.issue(
      **{ name: "Acme Robotics", email: "dana@acme-robotics.example", max_sessions: 5 }.merge(over)
    )
  end

  def acme = Company.find_by(email_domain: "acme-robotics.example")

  # -- A stranger ------------------------------------------------------------

  test "a stranger can open the form and is asked for an address" do
    get new_workspace_path

    assert_inertia_page "Workspaces/NewPage"
    assert_inertia_props { |props| assert props[:needsEmail] }
  end

  # The form asks for a number of sessions; this is what it costs to run them, and
  # what it does not.
  test "the form says how much capacity is free" do
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 250))

    get new_workspace_path

    assert_inertia_props { |props| assert_equal 250, props[:freeQueueHours] }
  end

  # Nothing is written on their say-so: the address is unproved until the link
  # sent to it comes back.
  test "a stranger's answers are emailed, not written" do
    assert_no_difference [ "Company.count", "User.count" ] do
      assert_enqueued_emails 1 do
        post workspace_path, params: valid_params
      end
    end

    assert_redirected_to new_workspace_path(sent: "dana@acme-robotics.example")
  end

  test "the screen says which inbox to open" do
    get new_workspace_path(sent: "dana@acme-robotics.example")

    assert_inertia_props { |props| assert_equal "dana@acme-robotics.example", props[:sentTo] }
  end

  test "answers that do not validate are not emailed" do
    assert_enqueued_emails 0 do
      post workspace_path, params: valid_params(max_sessions: "0")
    end
  end

  test "an address that is not one is refused before any mail goes out" do
    assert_enqueued_emails 0 do
      post workspace_path, params: valid_params(email: "dana at acme")
    end
  end

  # Refused before the mail goes out, so a squatter cannot even make us send to
  # an address at a service they do not own.
  test "a public mail service never reaches the inbox" do
    assert_enqueued_emails 0 do
      post workspace_path, params: valid_params(email: "dana@gmail.com")
    end

    assert_nil Company.find_by(email_domain: "gmail.com")
  end

  test "a domain that already has a workspace never reaches the inbox" do
    create(:company, email_domain: "acme-robotics.example")

    assert_enqueued_emails 0 do
      post workspace_path, params: valid_params
    end
  end

  # The page reads these keys, and the Inertia prop_transformer camelises every
  # prop on the way out — errors included. A refusal the server spells
  # email_domain arrives as emailDomain, and reading the other spelling swallows
  # it: the form comes back untouched with nothing to explain why.
  test "a refusal reaches the form under the key the page reads" do
    create(:company, email_domain: "acme-robotics.example")

    post workspace_path, params: valid_params
    follow_redirect!

    assert_inertia_props do |props|
      assert_match(/already has a workspace/, Array(props.dig(:errors, :emailDomain)).join)
    end
  end

  # -- The link --------------------------------------------------------------

  test "opening the link creates the workspace and signs its owner in" do
    get confirm_workspace_path(token: ticket)

    assert_redirected_to onboarding_path
    owner = User.find_by(email: "dana@acme-robotics.example")
    assert_equal "admin", owner.company_memberships.find_by(company: acme).role
    assert_equal 5, SessionConcurrencyLimit.for_company(acme.id)

    follow_redirect!
    assert_response :success
  end

  test "an existing account owns it rather than a second one" do
    existing = create(:user, email: "dana@acme-robotics.example")

    assert_no_difference "User.count" do
      get confirm_workspace_path(token: ticket)
    end

    assert_equal existing, acme.company_memberships.first.user
  end

  test "a tampered link creates nothing" do
    token = ticket

    assert_no_difference [ "Company.count", "User.count" ] do
      get confirm_workspace_path(token: "#{token}x")
    end

    assert_redirected_to new_workspace_path
  end

  test "an expired link creates nothing" do
    token = ticket
    travel WorkspaceSignupTicket::TTL + 1.minute

    assert_no_difference "Company.count" do
      get confirm_workspace_path(token: token)
    end
  end

  # The link is not single-use -- nothing is stored to mark it spent -- so the
  # unique domain is what stops a second click making a second workspace.
  test "opening the same link twice makes one workspace" do
    token = ticket
    get confirm_workspace_path(token: token)

    assert_no_difference "Company.count" do
      get confirm_workspace_path(token: token)
    end
  end

  test "a link for someone who already belongs somewhere is refused" do
    user = create(:user, email: "dana@acme-robotics.example")
    create(:company_membership, user: user, company: create(:company), state: "active")

    assert_no_difference "Company.count" do
      get confirm_workspace_path(token: ticket)
    end
  end

  # -- Someone already signed in ---------------------------------------------

  test "a signed-in person's workspace is created without an email round trip" do
    sign_in_as(create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD))

    assert_enqueued_emails 0 do
      post workspace_path, params: { workspace: { name: "Acme Robotics", max_sessions: "5" } }
    end

    assert_redirected_to onboarding_path
    assert_equal 5, SessionConcurrencyLimit.for_company(acme.id)
  end

  # Their address is the one they proved, whatever the form body claims.
  test "a signed-in person cannot claim a domain that is not theirs" do
    sign_in_as(create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD))

    post workspace_path, params: valid_params(email: "someone@northwind.example")

    assert_nil Company.find_by(email_domain: "northwind.example")
  end

  # The form could only refuse their domain, and the refusal was about a field a
  # signed-in person is never shown — so the page names the workspace instead.
  test "someone whose domain already has a workspace is shown the way into it" do
    create(:company, :auto_accept, name: "Acme Robotics", email_domain: "acme-robotics.example")
    sign_in_as(create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD))

    get new_workspace_path

    assert_inertia_props do |props|
      assert_equal "Acme Robotics", props.dig(:claimedDomain, :workspaceName)
      assert_includes props.dig(:claimedDomain, :joinMethods), "Google"
    end
  end

  test "a free domain gets the form" do
    sign_in_as(create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD))

    get new_workspace_path

    assert_inertia_props { |props| assert_nil props[:claimedDomain] }
  end

  test "someone who already belongs somewhere is sent away" do
    user = create(:user, password: AuthHelper::TEST_PASSWORD)
    create(:company_membership, user: user, company: create(:company), state: "active")
    sign_in_as(user)

    get new_workspace_path

    assert_redirected_to root_path
  end

  # Every other screen would render empty for someone with no company, so there
  # is one place for them to be until they have one.
  test "someone with no company is sent here from anywhere else" do
    sign_in_as(create(:user, password: AuthHelper::TEST_PASSWORD))

    get company_projects_path

    assert_redirected_to new_workspace_path
  end

  # -- Where this is not the product -----------------------------------------

  # The screens ship before the product is ready to take strangers, so they are
  # behind a flag an operator turns on — and a half-open door is worse than a
  # closed one, so it closes the form itself, not just the link to it.
  test "the form is closed while registration is off" do
    with_mode(Deployment::SAAS, registration: false)

    get new_workspace_path

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "no mail goes out while registration is off" do
    with_mode(Deployment::SAAS, registration: false)

    assert_enqueued_emails 0 do
      post workspace_path, params: valid_params
    end
  end

  test "a link issued before it was switched off creates nothing" do
    token = ticket
    with_mode(Deployment::SAAS, registration: false)

    assert_no_difference "Company.count" do
      get confirm_workspace_path(token: token)
    end
  end


  test "self-hosted refuses the whole path" do
    with_mode(Deployment::SELF_HOSTED)

    get new_workspace_path

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "marketplace refuses the link too" do
    with_mode(Deployment::AWS_MARKETPLACE)

    assert_no_difference "Company.count" do
      get confirm_workspace_path(token: ticket)
    end
  end

  # -- The calculator's hand-off ---------------------------------------------

  test "the form opens on the queue count the calculator sent" do
    get new_workspace_path(sessions: 9)

    assert_inertia_props { |props| assert_equal 9, props[:defaultMaxSessions] }
  end

  test "a nonsense queue count falls back to the installation default" do
    get new_workspace_path(sessions: "lots")

    assert_inertia_props do |props|
      assert_equal SessionAdmissionPolicy.scope_default("Project"), props[:defaultMaxSessions]
    end
  end
end
