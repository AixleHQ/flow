# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SettingsInsightsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @collaborator = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project.add_collaborator(@collaborator)
    @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  test "owner can enable insights sharing" do
    sign_in_as @owner

    patch company_project_settings_path(@project),
          params: { project: { share_usage_with_insights: true } }

    assert_redirected_to company_project_settings_path(@project)
    assert @project.reload.share_usage_with_insights?
  end

  test "company admin can enable insights sharing" do
    sign_in_as @admin

    patch company_project_settings_path(@project),
          params: { project: { share_usage_with_insights: true } }

    assert_redirected_to company_project_settings_path(@project)
    assert @project.reload.share_usage_with_insights?
  end

  test "collaborator cannot enable insights sharing" do
    sign_in_as @collaborator

    patch company_project_settings_path(@project),
          params: { project: { share_usage_with_insights: true } }

    assert_redirected_to company_project_settings_path(@project)
    assert_equal "Not authorized to manage Insights sharing", flash[:alert]
    assert_not @project.reload.share_usage_with_insights?
  end

  test "owner can regenerate insights connection token when sharing is on" do
    @project.update!(share_usage_with_insights: true)
    sign_in_as @owner

    post regenerate_insights_connection_token_company_project_settings_path(@project)

    assert_redirected_to company_project_settings_path(@project)
    assert @project.reload.insights_connection_configured?
    follow_redirect!
    assert_inertia_props do |props|
      assert props[:project][:insightsConnectionToken].present?
    end
  end

  test "collaborator cannot regenerate insights connection token" do
    @project.update!(share_usage_with_insights: true)
    sign_in_as @collaborator

    post regenerate_insights_connection_token_company_project_settings_path(@project)

    assert_response :redirect
    assert_equal "You are not authorized to perform this action.", flash[:alert]
    assert_not @project.reload.insights_connection_configured?
  end

  test "settings show includes insights props for owner" do
    sign_in_as @owner
    get company_project_settings_path(@project)

    assert_response :success
    assert_inertia_props do |props|
      project = props[:project]
      assert_equal false, project[:shareUsageWithInsights]
      assert_equal false, project[:insightsConnectionConfigured]
      assert_equal true, project[:canManageInsightsSharing]
      assert_nil project[:insightsConnectionToken]
    end
  end

  test "settings show marks collaborator as unable to manage insights sharing" do
    sign_in_as @collaborator
    get company_project_settings_path(@project)

    assert_response :success
    assert_inertia_props do |props|
      assert_equal false, props[:project][:canManageInsightsSharing]
    end
  end
end
