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

  test "new renders new session page" do
    get new_company_session_path
    assert_inertia_page "Company/Sessions/New"
  end

  test "show renders session detail page" do
    session = create(:terminal_session, user: @user, project: create(:project, company: @company, owner: @user))
    get company_session_path(session)
    assert_inertia_page "Company/Sessions/Show"
  end
end
