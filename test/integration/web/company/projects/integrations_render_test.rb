# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::IntegrationsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    # visible_for_project surfaces project-scoped integrations for this project.
    @integration = create(:integration, :active, company: @company, project: @project, connected_by: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the integrations page" do
    get company_project_integrations_path(@project)
    assert_response :success
    assert_inertia_page "Projects/Integrations/IntegrationsPage"
    assert_inertia_props do |props|
      props[:integrations].size == 1
    end
  end
end
