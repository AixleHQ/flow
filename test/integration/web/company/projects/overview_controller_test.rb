# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::OverviewControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders overview page" do
    get company_project_overview_index_path(@project)
    assert_inertia_page "Projects/Overview/OverviewPage"
  end

  test "summary reports the count of currently running sessions" do
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "not_started")
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "running")
    create(:terminal_session, :agent_session, project: @project, user: @user, state: "ready")

    get company_project_overview_index_path(@project)

    assert_inertia_props do |props|
      props[:summary][:sessionsLaunched] == 3 && props[:summary][:sessionsRunning] == 2
    end
  end
end
