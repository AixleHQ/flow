# frozen_string_literal: true

require "test_helper"

class Web::Company::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders analytics page with default scope and period" do
    get company_analytics_path
    assert_inertia_page "Company/Analytics/AnalyticsPage"
    assert_inertia_props scope: "company", period: "30d"
  end

  test "index passes custom period" do
    get company_analytics_path(period: "7d")
    assert_inertia_page "Company/Analytics/AnalyticsPage"
    assert_inertia_props period: "7d"
  end

  test "index declares all analytics props as deferred" do
    get company_analytics_path

    assert_inertia_deferred_props :summary, :agent_activity, :sources, :cost_token,
                                  group: "analytics"
  end

  test "deferred props resolve after partial reload" do
    get company_analytics_path
    assert_inertia_page "Company/Analytics/AnalyticsPage"

    inertia_load_deferred_props("analytics")

    assert_inertia_props summary: {
      totalSessions: 0,
      totalCostCents: 0,
      totalTokens: 0,
      avgCostCentsPerSession: 0,
      workflowsRun: 0,
      projectBreakdowns: []
    }
  end

  test "deferred props return real data when sessions exist" do
    session = build(:terminal_session, project: @project, user: @user,
                    session_type: "agent_session", agent_type: "coding")
    session.save!(validate: false)

    get company_analytics_path
    inertia_load_deferred_props("analytics")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:projectBreakdowns].length == 1 &&
        props[:summary][:projectBreakdowns].first[:projectName] == @project.name
    end
  end
end
