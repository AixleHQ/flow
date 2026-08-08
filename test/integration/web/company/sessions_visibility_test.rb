# frozen_string_literal: true

require "test_helper"

# The company-wide sessions screen is admin-only, and admin rights are what get
# you to the LIST — they are not a key to the sessions on it. The owner's
# profile preferences apply to every other person in the product, admins
# included: the setting exists to keep colleagues out of a live shell, and an
# exemption for the role most likely to look would empty it.
class Web::Company::SessionsVisibilityTest < ActionDispatch::IntegrationTest
  DENIAL_ALERT = "You are not authorized to perform this action."

  setup do
    @company = create(:company)
    @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @member = create(:user, :employee, :onboarding_completed, company: @company,
                                                              share_active_sessions: false,
                                                              share_completed_sessions: true,
                                                              password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @member)

    sign_in_as(@admin)
    # See the project-scoped visibility test: a denial returns before the
    # eager-loaded associations are read, which trips Bullet's
    # unused-eager-loading gate.
    Bullet.enable = false
  end

  teardown { Bullet.enable = true }

  test "an admin cannot open a member's running session they do not share" do
    session = create(:terminal_session, :agent_session, :running, user: @member, project: @project)

    get company_session_path(session)

    assert_response :redirect
    assert_equal DENIAL_ALERT, flash[:alert]
  end

  test "an admin opens a member's finished session while it is shared" do
    session = create(:terminal_session, :agent_session, :collected, user: @member, project: @project)

    get company_session_path(session)

    assert_inertia_page "Company/Sessions/Show"
  end

  test "the company list keeps the row and its spend, minus the prompt" do
    session = create(:terminal_session, :agent_session, :running, user: @member, project: @project,
                                                                  initial_prompt: "refactor the billing module")

    get company_sessions_path

    assert_response :success
    row = inertia.props[:sessions].find { |s| s[:id] == session.id }

    assert_equal false, row[:viewable] # rubocop:disable Minitest/RefuteFalse
    assert_nil row[:initialPrompt]
    assert_equal session.cost_cents, row[:costCents]
  end
end
