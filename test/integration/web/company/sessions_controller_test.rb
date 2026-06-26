# frozen_string_literal: true

require "test_helper"

class Web::Company::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders sessions page" do
    get company_sessions_path
    assert_inertia_page "Company/Sessions/Index"
  end

  test "index loads session list without N+1 queries" do
    project = create(:project, company: @company, owner: @user)
    tool = create(:tool, scope: @company)
    sessions = create_list(:terminal_session, 2, :agent_session, user: @user, project: project)
    sessions.each do |s|
      s.tools << tool
      create(:session_log, terminal_session: s)
    end

    get company_sessions_path
    assert_inertia_page "Company/Sessions/Index"
  end

  test "show renders session detail page" do
    session = create(:terminal_session, user: @user, project: create(:project, company: @company, owner: @user))
    get company_session_path(session)
    assert_inertia_page "Company/Sessions/Show"
  end
end
