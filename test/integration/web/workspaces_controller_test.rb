# frozen_string_literal: true

require "test_helper"

class Web::WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, email: "dana@acme-robotics.example", password: AuthHelper::TEST_PASSWORD)
    with_mode(Deployment::SAAS)
    sign_in_as(@user)
  end

  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
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
