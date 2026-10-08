# frozen_string_literal: true

require "test_helper"

class Web::HomeControllerTest < ActionDispatch::IntegrationTest
  def with_mode(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  # Non-Inertia: layout web/landing, empty HTML shell — no assert_inertia_page.
  test "show renders landing for root path" do
    get root_path
    assert_response :success
  end

  test "a hosted or self-hosted installation shows the landing page" do
    [ Deployment::SAAS, Deployment::SELF_HOSTED ].each do |mode|
      with_mode(mode)

      get root_path

      assert_response :success, mode
    end
  end

  test "a Marketplace installation sends a stranger to sign in instead of the landing page" do
    with_mode(Deployment::AWS_MARKETPLACE)

    get root_path

    assert_redirected_to login_path
  end

  test "a Marketplace installation sends a signed-in member to their projects" do
    company = create(:company)
    sign_in_as(create(:user, :admin, :onboarding_completed, company: company, password: AuthHelper::TEST_PASSWORD))
    with_mode(Deployment::AWS_MARKETPLACE)

    get root_path

    assert_redirected_to company_projects_path
  end
end
