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

  test "index is denied for an employee (non-admin)" do
    employee = create(:user, :employee, :onboarding_completed, company: @company,
                                                               password: AuthHelper::TEST_PASSWORD)
    sign_in_as(employee)

    get company_sessions_path

    # Authorization gate fires: 302 redirect + not-authorized alert (not a 403 — see design doc
    # DECISION 1), landing on root_path (redirect_back fallback, no Referer in the request).
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end

  test "show is denied for an employee (non-admin)" do
    session = create(:terminal_session, user: @user, project: create(:project, company: @company, owner: @user))
    employee = create(:user, :employee, :onboarding_completed, company: @company,
                                                               password: AuthHelper::TEST_PASSWORD)
    sign_in_as(employee)

    get company_session_path(session)

    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "You are not authorized to perform this action.", flash[:alert]
  end
end
