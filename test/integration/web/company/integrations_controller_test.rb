# frozen_string_literal: true

require "test_helper"

class Web::Company::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders integrations page" do
    create(:integration, company: @company, connected_by: @user)

    get company_integrations_path
    assert_inertia_page "Company/Integrations/Index"
  end

  test "create gitlab integration redirects" do
    Gitlab::IntegrationService.any_instance.stubs(:create).returns(
      create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    )

    post company_integrations_path, params: { provider: "gitlab", personal_access_token: "glpat-test" }
    assert_response :redirect
  end

  test "create with unsupported provider redirects with alert" do
    post company_integrations_path, params: { provider: "unsupported" }
    assert_response :redirect
  end

  test "destroy removes integration" do
    integration = create(:integration, company: @company, connected_by: @user)

    delete company_integration_path(integration)
    assert_response :redirect
  end
end
