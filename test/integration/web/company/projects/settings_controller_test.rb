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

  # == session concurrency ==

  def limit_for(project) = SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: project.id)

  test "a company admin sets the project's session limit from its own settings" do
    patch company_project_settings_path(@project), params: {
      project: { name: @project.name }, concurrency: "6"
    }

    assert_response :redirect
    assert_equal 6, limit_for(@project).max_sessions
  end

  test "clearing the field puts the project back on the installation default" do
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 6)

    patch company_project_settings_path(@project), params: {
      project: { name: @project.name }, concurrency: ""
    }

    assert_nil limit_for(@project), "an empty limit is no reservation, not a reservation of nothing"
  end

  test "a limit past what the installation has left is refused and says what is left" do
    SessionAdmissionPolicy.sync!(installation_limit: 10)
    other = create(:project, company: @company, owner: @user)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 7)

    patch company_project_settings_path(@project), params: {
      project: { name: @project.name }, concurrency: "5"
    }

    assert_nil limit_for(@project)
    error = Array(session["inertia_errors"][:concurrency]).to_sentence
    assert_match(/installation limit of 10/, error)
    assert_match(/7 of 10/, error)
    assert_match(/at most 3/, error)
  end

  # "Settings were not saved" has to be true of all of them, or the person is
  # left guessing which half landed.
  test "a refused limit rolls back the rest of the save" do
    SessionAdmissionPolicy.sync!(installation_limit: 2)
    other = create(:project, company: @company, owner: @user)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 2)

    patch company_project_settings_path(@project), params: {
      project: { name: "Renamed Project" }, concurrency: "2"
    }

    assert_equal @project.name, @project.reload.name, "the name must not survive a refused save"
  end

  test "a member who is not a company admin cannot set the limit" do
    member = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    create(:project_collaborator, project: @project, user: member)
    sign_in_as(member)

    patch company_project_settings_path(@project), params: {
      project: { name: @project.name }, concurrency: "6"
    }

    assert_nil limit_for(@project)
    assert_match(/company admin/, Array(session["inertia_errors"][:concurrency]).to_sentence)
  end

  test "a save that carries no limit at all leaves the existing one alone" do
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 6)

    patch company_project_settings_path(@project), params: { project: { name: "Renamed Project" } }

    assert_equal 6, limit_for(@project).max_sessions
  end
end
