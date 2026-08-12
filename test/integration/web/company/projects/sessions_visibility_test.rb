# frozen_string_literal: true

require "test_helper"

# Project members can reach every session in their project — that is the scoping
# rule, and it has not changed. What changed is that reaching a session is no
# longer enough to OPEN it: the owner's profile decides who may watch them work
# while a session runs, and who may replay its log once it is over
# (TerminalSession#visible_to?).
#
# Denial is the standard web contract: 302 + the "not authorized" flash.
class Web::Company::Projects::SessionsVisibilityTest < ActionDispatch::IntegrationTest
  DENIAL_ALERT = "You are not authorized to perform this action."

  setup do
    @company = create(:company)
    @owner = create(:user, :employee, :onboarding_completed, company: @company,
                                                             share_active_sessions: false,
                                                             share_completed_sessions: true,
                                                             password: AuthHelper::TEST_PASSWORD)
    @member = create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@member)

    sign_in_as(@member)
    # Same reason AuthorizationMatrix disables it: these assert who may open a
    # session, and a denial returns before the eager-loaded association is ever
    # read, which trips Bullet's unused-eager-loading gate. Query shape is owned
    # by the controller tests.
    Bullet.enable = false
  end

  teardown { Bullet.enable = true }

  test "a running session another member does not share cannot be opened" do
    session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)

    get company_project_session_path(@project, session)

    assert_response :redirect
    assert_equal DENIAL_ALERT, flash[:alert]
  end

  test "a running session opens once its owner shares active sessions" do
    @owner.update!(share_active_sessions: true)
    session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)

    get company_project_session_path(@project, session)

    assert_inertia_page "Projects/Sessions/ShowPage"
    assert_equal session.route_token, inertia.props[:session][:routeToken]
    # Drives the watch-only presentation (shield over the terminal, no editor,
    # no Finish) — see SessionShowContent.
    assert_equal false, inertia.props[:session][:ownedByViewer] # rubocop:disable Minitest/RefuteFalse
  end

  test "a finished session opens while its owner shares finished sessions" do
    session = create(:terminal_session, :agent_session, :collected, user: @owner, project: @project)

    get company_project_session_path(@project, session)

    assert_inertia_page "Projects/Sessions/ShowPage"
    assert inertia.props[:session][:viewable]
  end

  test "a finished session stops opening once its owner turns finished sharing off" do
    @owner.update!(share_completed_sessions: false)
    session = create(:terminal_session, :agent_session, :collected, user: @owner, project: @project)

    get company_project_session_path(@project, session)

    assert_response :redirect
    assert_equal DENIAL_ALERT, flash[:alert]
  end

  test "the owner always opens their own session, sharing nothing" do
    @owner.update!(share_active_sessions: false, share_completed_sessions: false)
    session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project)
    sign_in_as(@owner)

    get company_project_session_path(@project, session)

    assert_inertia_page "Projects/Sessions/ShowPage"
    assert inertia.props[:session][:ownedByViewer]
  end

  test "the list keeps a private session's row but not what it was working on" do
    private_session = create(:terminal_session, :agent_session, :running, user: @owner, project: @project,
                                                                          initial_prompt: "refactor the billing module")
    own_session = create(:terminal_session, :agent_session, :running, user: @member, project: @project,
                                                                      initial_prompt: "fix the importer")

    get company_project_sessions_path(@project)

    assert_response :success
    rows = inertia.props[:entries].index_by { |e| e[:id] }

    # The row survives — cost and token columns are how a team sees what its
    # project spends, and hiding the row would take that with it. What goes is
    # the content: the row's name is drawn from the prompt, which says what the
    # person is doing, and nothing else in the stack protects it.
    assert_equal false, rows[private_session.id][:viewable] # rubocop:disable Minitest/RefuteFalse
    assert_equal "Interactive session", rows[private_session.id][:name]

    assert rows[own_session.id][:viewable]
    assert_equal "fix the importer", rows[own_session.id][:name]
  end

  test "artifacts of a private session are refused too" do
    @owner.update!(share_completed_sessions: false)
    session = create(:terminal_session, :agent_session, :collected, user: @owner, project: @project)

    get company_project_session_artifacts_path(@project, session)

    assert_response :redirect
    assert_equal DENIAL_ALERT, flash[:alert]
  end

  test "workflow-step sessions stay open to the project regardless of preferences" do
    @owner.update!(share_active_sessions: false, share_completed_sessions: false)
    session = create(:terminal_session, :running, session_type: "workflow_step", user: @owner, project: @project)

    get company_project_session_path(@project, session)

    assert_inertia_page "Projects/Sessions/ShowPage"
  end
end
