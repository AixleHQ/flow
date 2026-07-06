# frozen_string_literal: true

require "application_system_test_case"

# E2E critical path: an authenticated user creates a project end to end (Inertia
# form POST -> Rails -> reloaded list), through a headless browser.
class ProjectManagementTest < ApplicationSystemTestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company,
                                  password: AuthHelper::TEST_PASSWORD)
    LoginPage.new.tap(&:load).sign_in(@user.email, AuthHelper::TEST_PASSWORD)
  end

  test "an authenticated user creates a project" do
    assert_current_path "/company/projects", wait: 10
    projects = ProjectsPage.new

    projects.create_project(name: "Launch Rocket")

    assert_text "Launch Rocket", wait: 10
    assert @company.projects.exists?(name: "Launch Rocket"), "project persisted"
  end
end
