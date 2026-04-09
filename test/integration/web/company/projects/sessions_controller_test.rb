# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders sessions page" do
    get company_project_sessions_path(@project)
    assert_inertia_page "Projects/Sessions/SessionsPage"
  end

  test "new renders new session page" do
    get new_company_project_session_path(@project)
    assert_inertia_page "Projects/Sessions/NewPage"
  end

  test "show renders session page" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    get company_project_session_path(@project, session)
    assert_inertia_page "Projects/Sessions/ShowPage"
  end
end
