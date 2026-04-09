# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "show renders settings page" do
    get company_project_settings_path(@project)
    assert_inertia_page "Projects/Settings/SettingsPage"
  end

  test "update redirects on success" do
    patch company_project_settings_path(@project), params: {
      project: { name: "Renamed Project" }
    }
    assert_response :redirect
  end
end
