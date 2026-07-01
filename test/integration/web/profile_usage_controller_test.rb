# frozen_string_literal: true

require "test_helper"

class Web::ProfileUsageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  def seed_session(user:, project:, cost_cents: 150, tokens: 1500, session_type: "agent_session",
                   agent_type: "claude_code", created_at: Time.current)
    session = build(:terminal_session, user:, project:, session_type:, agent_type:, created_at:)
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents:, input_tokens: tokens, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens:
    )
    session
  end

  test "renders usage page with default period and self as target" do
    get usage_profile_path
    assert_inertia_page "Profile/Usage"
    assert_inertia_props period: "30d", viewerIsSelf: true
    assert_inertia_props do |props|
      props[:targetUser][:id] == @user.id
    end
  end

  test "passes custom period" do
    get usage_profile_path(period: "7d")
    assert_inertia_props period: "7d"
  end

  test "declares all usage props as deferred" do
    get usage_profile_path
    assert_inertia_deferred_props :summary, :agent_activity, :cost_token,
                                  :activity_heatmap, :sessions, group: "usage"
  end

  test "deferred props resolve to zeros for an empty user" do
    get usage_profile_path
    inertia_load_deferred_props("usage")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 0 &&
        props[:summary][:projectBreakdowns] == [] &&
        props[:activityHeatmap][:days] == [] &&
        props[:sessions] == []
    end
  end

  test "deferred props return real data when sessions exist" do
    seed_session(user: @user, project: @project)

    get usage_profile_path
    inertia_load_deferred_props("usage")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:totalCostCents] == 150 &&
        props[:summary][:totalTokens] == 1500 &&
        props[:summary][:projectBreakdowns].length == 1 &&
        props[:activityHeatmap][:days].length == 1 &&
        props[:sessions].length == 1
    end
  end

  test "reconciliation holds across the controller with a project-less session" do
    seed_session(user: @user, project: @project, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: nil, cost_cents: 250, tokens: 500)

    get usage_profile_path
    inertia_load_deferred_props("usage")

    assert_inertia_props do |props|
      s = props[:summary]
      breakdowns = s[:projectBreakdowns]
      breakdowns.sum { |p| p[:sessions] } == s[:totalSessions] &&
        breakdowns.sum { |p| p[:costCents] } == s[:totalCostCents] &&
        breakdowns.sum { |p| p[:tokens] } == s[:totalTokens] &&
        breakdowns.count { |p| p[:projectName] == "(No project)" } == 1
    end
  end

  test "cross-person same company member view is allowed and reflects target data" do
    user_b = create(:user, :employee, :onboarding_completed, company: @company)
    seed_session(user: user_b, project: @project, cost_cents: 300, tokens: 3000)

    get usage_profile_path(user_id: user_b.id)
    assert_inertia_props viewerIsSelf: false
    assert_inertia_props do |props|
      props[:targetUser][:id] == user_b.id
    end

    inertia_load_deferred_props("usage")
    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:totalCostCents] == 300
    end
  end

  test "cross-company target is forbidden with 404" do
    other_company = create(:company)
    user_c = create(:user, :employee, :onboarding_completed, company: other_company)

    get usage_profile_path(user_id: user_c.id)
    assert_response :not_found
  end

  test "self default when user_id is absent" do
    get usage_profile_path
    assert_inertia_props do |props|
      props[:targetUser][:id] == @user.id && props[:viewerIsSelf] == true
    end
  end

  test "super_admin is redirected away from profile usage" do
    delete logout_path
    super_admin = create(:user, :super_admin, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(super_admin)

    get usage_profile_path
    assert_redirected_to admin_root_path
  end

  test "unauthenticated request is redirected to login" do
    delete logout_path
    get usage_profile_path
    assert_redirected_to login_path
  end
end
