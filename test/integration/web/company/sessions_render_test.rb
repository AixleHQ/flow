# frozen_string_literal: true

require "test_helper"

class Web::Company::SessionsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # the index list page trips the unused-eager-loading gate
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the sessions page" do
    # index excludes session_type "auth_setup", so seed an agent_session to populate the list.
    create(:terminal_session, :agent_session, user: @user, project: @project)

    get company_sessions_path
    assert_response :success
    assert_inertia_page "Company/Sessions/Index"
  end

  test "show renders a session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    get company_session_path(session)
    assert_response :success
    assert_inertia_page "Company/Sessions/Show"

    assert_inertia_props do |props|
      props[:session][:id] == session.id
    end
  end
end
