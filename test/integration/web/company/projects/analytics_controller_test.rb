# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders analytics page with default scope and period" do
    get company_project_analytics_path(@project)
    assert_inertia_page "Projects/Analytics/AnalyticsPage"
    assert_inertia_props scope: "project", period: "30d"
  end

  test "index passes custom scope and period" do
    get company_project_analytics_path(@project, scope: "user", period: "7d")
    assert_inertia_page "Projects/Analytics/AnalyticsPage"
    assert_inertia_props scope: "user", period: "7d"
  end

  test "index declares all analytics props as deferred" do
    get company_project_analytics_path(@project)

    assert_inertia_deferred_props :summary, :agent_activity, :sources,
                                  :duration, :cost_token, :workflow_costs,
                                  group: "analytics"
  end

  test "deferred props resolve after partial reload" do
    get company_project_analytics_path(@project)
    assert_inertia_page "Projects/Analytics/AnalyticsPage"

    inertia_load_deferred_props("analytics")

    assert_inertia_props summary: {
      totalSessions: 0,
      totalCostCents: 0,
      totalTokens: 0,
      avgCostCentsPerSession: 0,
      workflowsRun: 0
    }
  end

  test "deferred props return real data when sessions exist" do
    session = build(:terminal_session, project: @project, user: @user,
                    session_type: "agent_session", agent_type: "coding")
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 150,
      input_tokens: 1000, output_tokens: 500,
      cache_write_tokens: 0, cache_read_tokens: 0,
      tokens: 1500
    )

    get company_project_analytics_path(@project)
    inertia_load_deferred_props("analytics")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:totalCostCents] == 150 &&
        props[:summary][:totalTokens] == 1500
    end
  end
end
