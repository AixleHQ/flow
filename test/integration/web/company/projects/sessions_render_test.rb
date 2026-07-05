# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Sessions controller renders three
# Inertia pages — Projects/Sessions/SessionsPage (#index),
# Projects/Sessions/NewPage (#new) and Projects/Sessions/ShowPage (#show).
# Happy-path render contract, complementing sessions_authorization_test.rb
# (permit/forbid matrix).
class Web::Company::Projects::SessionsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # eager-loaded collections trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the sessions page with the project's sessions" do
    session = create(:terminal_session, :agent_session, project: @project, user: @user)

    get company_project_sessions_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Sessions/SessionsPage"
    assert_inertia_props do |props|
      props[:sessions].any? { |s| s[:id] == session.id }
    end
  end

  test "new renders the new session page" do
    get new_company_project_session_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Sessions/NewPage"
  end

  test "show renders a session" do
    session = create(:terminal_session, :agent_session, project: @project, user: @user)

    get company_project_session_path(@project, session)

    assert_response :success
    assert_inertia_page "Projects/Sessions/ShowPage"
    assert_inertia_props do |props|
      props[:session].present? && props[:session][:id] == session.id
    end
  end
end
