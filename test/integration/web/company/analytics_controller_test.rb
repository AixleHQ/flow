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

  test "index is denied for an employee (non-admin)" do
    employee = create(:user, :employee, :onboarding_completed, company: @company,
                                                               password: AuthHelper::TEST_PASSWORD)
    sign_in_as(employee)

    get company_analytics_path

    # Authorization gate fires: 302 redirect + not-authorized alert (not a 403 — see design doc
    # DECISION 1), landing on root_path (redirect_back fallback, no Referer in the request).
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "You are not authorized to perform this action.", flash[:alert]
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
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 150,
      input_tokens: 1000, output_tokens: 500,
      cache_write_tokens: 0, cache_read_tokens: 0,
      tokens: 1500
    )

    get company_analytics_path
    inertia_load_deferred_props("analytics")

    assert_inertia_props do |props|
      props[:summary][:totalSessions] == 1 &&
        props[:summary][:totalCostCents] == 150 &&
        props[:summary][:totalTokens] == 1500 &&
        props[:summary][:projectBreakdowns].length == 1 &&
        props[:summary][:projectBreakdowns].first[:projectName] == @project.name
    end
  end
end
