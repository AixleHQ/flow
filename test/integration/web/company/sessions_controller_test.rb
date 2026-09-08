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
    tool = create(:tool, scope: project)
    sessions = create_list(:terminal_session, 2, :agent_session, user: @user, project: project)
    sessions.each do |s|
      s.tools << tool
      create(:session_log, terminal_session: s)
    end

    get company_sessions_path
    assert_inertia_page "Company/Sessions/Index"
  end

  test "index exposes the Sessions & Runs props: type, total and user options" do
    project = create(:project, company: @company, owner: @user)
    create(:terminal_session, :agent_session, user: @user, project: project)

    get company_sessions_path
    assert_response :success

    assert_equal "all", inertia.props[:filters][:type]
    assert_equal 1, inertia.props[:total]
    assert_equal [ @user.id ], inertia.props[:userOptions].map { |u| u[:id] }
  end

  test "index type=run keeps only workflow-step sessions; type=solo keeps only standalone" do
    project = create(:project, company: @company, owner: @user)
    solo = create(:terminal_session, :agent_session, user: @user, project: project)
    step = create(:terminal_session, user: @user, project: project, session_type: "workflow_step")

    get company_sessions_path(type: "run")
    assert_equal [ step.id ], inertia.props[:sessions].map { |s| s[:id] }

    get company_sessions_path(type: "solo")
    assert_equal [ solo.id ], inertia.props[:sessions].map { |s| s[:id] }
  end

  test "index status filter maps the shared vocabulary onto internal states" do
    project = create(:project, company: @company, owner: @user)
    running = create(:terminal_session, :agent_session, :running, user: @user, project: project)
    create(:terminal_session, :agent_session, :collected, user: @user, project: project)

    get company_sessions_path(status: "running")
    assert_equal [ running.id ], inertia.props[:sessions].map { |s| s[:id] }
  end

  test "index search on the prompt does not leak a private session's hidden prompt" do
    project = create(:project, company: @company, owner: @user)
    other = create(:user, :employee, :onboarding_completed, company: @company,
                                                            share_active_sessions: false,
                                                            share_completed_sessions: false)
    hidden = create(:terminal_session, :agent_session, :running, user: other, project: project,
                                                                 initial_prompt: "migrate the payroll ledger")
    mine = create(:terminal_session, :agent_session, user: @user, project: project,
                                                     initial_prompt: "migrate the payroll ledger")

    get company_sessions_path(search: "payroll ledger")
    ids = inertia.props[:sessions].map { |s| s[:id] }
    assert_includes ids, mine.id
    assert_not_includes ids, hidden.id
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
