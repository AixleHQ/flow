# frozen_string_literal: true

require "test_helper"

class Web::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD)
    with_mode(Deployment::SAAS)
    sign_in_as(@user)
  end

  # Registration is off by default, so a suite about signing up says so rather
  # than inheriting whatever the environment left in the settings file.
  def with_mode(mode, registration: true)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: registration))
  end

  def valid_params
    { workspace: { name: "Acme Robotics", email_domain: "acme-robotics.example", max_sessions: "5" } }
  end

  test "shows the form to someone who belongs nowhere" do
    get new_workspace_path

    assert_inertia_page "Workspaces/NewPage"
    assert_inertia_props { |props| assert_equal "acme-robotics.example", props[:suggestedDomain] }
  end

  test "creating a workspace makes its creator the admin" do
    post workspace_path, params: valid_params

    assert_response :redirect
    company = Company.find_by(email_domain: "acme-robotics.example")
    assert_equal "admin", @user.company_memberships.find_by(company: company).role
    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
  end

  # The /how-it-works calculator works out a queue count and links here with it.
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

  test "a workspace cannot be signed up without a limit" do
    post workspace_path, params: { workspace: { name: "Acme", email_domain: "acme-robotics.example" } }

    assert_nil Company.find_by(email_domain: "acme-robotics.example")
  end

  # Every other screen would render empty for someone with no company, so there
  # is one place for them to be until they have one.
  test "someone with no company is sent here from anywhere else" do
    get company_projects_path

    assert_redirected_to new_workspace_path
  end

  test "someone who already belongs somewhere is sent away" do
    create(:company_membership, user: @user, company: create(:company), state: "active")

    get new_workspace_path

    assert_response :redirect
    assert_not_equal new_workspace_path, response.location
  end

  # The screens ship before the product is ready to take strangers, so they are
  # behind a flag an operator turns on — and a half-open door is worse than a
  # closed one, so it closes the form, not just the link to it.
  test "the form is closed while registration is off" do
    with_mode(Deployment::SAAS, registration: false)

    get new_workspace_path

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "nothing can be created while registration is off" do
    with_mode(Deployment::SAAS, registration: false)

    post workspace_path, params: valid_params

    assert_nil Company.find_by(email_domain: "acme-robotics.example")
  end

  # Signing yourself up is the hosted product only: elsewhere a workspace is made
  # in the admin, and someone with no membership is a refusal.
  test "self-hosted refuses the whole path" do
    with_mode(Deployment::SELF_HOSTED)

    get new_workspace_path

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "marketplace refuses the whole path" do
    with_mode(Deployment::AWS_MARKETPLACE)

    post workspace_path, params: valid_params

    assert_nil Company.find_by(email_domain: "acme-robotics.example")
  end

  test "signing out is still possible from the form" do
    get new_workspace_path

    assert_response :success
  end
end
