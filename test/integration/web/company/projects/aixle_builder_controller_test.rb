# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AixleBuilderControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  # ── show ──────────────────────────────────────────

  test "show renders landing page" do
    get company_project_aixle_builder_path(@project)
    assert_inertia_page "Projects/AixleBuilder/LandingPage"
  end

  test "show includes sessions in response" do
    create(:terminal_session, :aixle_builder, user: @user, project: @project)

    get company_project_aixle_builder_path(@project)
    assert_inertia_page "Projects/AixleBuilder/LandingPage"
  end

  # ── start ─────────────────────────────────────────

  test "start creates session and redirects to session page" do
    SessionService.stubs(:create_and_start).returns(
      create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)
    )

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }
    assert_response :redirect
    assert_match %r{/aixle_builder/\d+/session}, response.location
  end

  test "start attaches existing meta tools to the session" do
    meta_tool = create(:tool, :meta, name: "meta_create_workflow")
    create(:tool, :workflow, name: "board_list_tasks") # must NOT be attached

    captured = nil
    SessionService.stubs(:create_and_start).with do |**kwargs|
      captured = kwargs
      true
    end.returns(create(:terminal_session, :aixle_builder, :started, user: @user, project: @project))

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }

    assert_response :redirect
    # Regression: meta_* tools were moved from kind :workflow to :meta by
    # migration 20260627000002, but the controller kept querying :workflow,
    # so Builder sessions were created with zero tools.
    assert_equal [ meta_tool.id ], captured[:params][:tool_ids]
  end

  test "start redirects back with flash alert when session save fails" do
    unsaved = TerminalSession.new
    unsaved.errors.add(:base, "Test validation failure")
    SessionService.stubs(:create_and_start).returns(unsaved)

    post company_project_aixle_builder_start_path(@project), params: { agent_runtime: "claude_code" }
    assert_redirected_to company_project_aixle_builder_path(@project)
    assert_equal "Test validation failure", flash[:alert]
  end

  # ── session ───────────────────────────────────────

  test "session renders session page for own session" do
    ts = create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)

    get company_project_aixle_builder_session_path(@project, ts)
    assert_inertia_page "Projects/AixleBuilder/SessionPage"
  end

  test "session returns 404 for another users session" do
    other_user = create(:user, company: @company)
    ts = create(:terminal_session, :aixle_builder, user: other_user, project: @project)

    get company_project_aixle_builder_session_path(@project, ts)
    assert_response :not_found
  end

  # ── finish ────────────────────────────────────────

  test "finish delegates to SessionService and redirects" do
    ts = create(:terminal_session, :aixle_builder, :started, user: @user, project: @project)
    SessionService.stubs(:finish)

    post company_project_aixle_builder_finish_path(@project, ts)
    assert_redirected_to company_project_aixle_builder_session_path(@project, ts)
  end
end
