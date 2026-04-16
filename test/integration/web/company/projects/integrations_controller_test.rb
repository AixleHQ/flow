# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders integrations page" do
    get company_project_integrations_path(@project)
    assert_inertia_page "Projects/Integrations/IntegrationsPage"
  end

  test "destroy removes integration" do
    integration = create(:integration, company: @company, connected_by: @user, project: @project)

    delete company_project_integration_path(@project, integration)
    assert_response :redirect
  end
end
