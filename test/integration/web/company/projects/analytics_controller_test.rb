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

  test "index declares all analytics props as deferred including the heatmap" do
    get company_project_analytics_path(@project)

    assert_inertia_deferred_props :summary, :agent_activity, :sources,
                                  :duration, :cost_token, :workflow_costs,
                                  :activity_heatmap,
                                  group: "analytics"
  end

  test "index exposes participants for the participant filter" do
    collaborator = create(:user, :employee, company: @company)
    create(:project_collaborator, project: @project, user: collaborator)

    get company_project_analytics_path(@project)

    assert_inertia_props do |props|
      ids = props[:participants].map { |p| p[:id] }
      ids.include?(@user.id) && ids.include?(collaborator.id)
    end
  end

  test "heatmap counts all participants by default" do
    collaborator = create(:user, :employee, company: @company)
    create(:project_collaborator, project: @project, user: collaborator)
    [ @user, collaborator ].each do |u|
      s = build(:terminal_session, project: @project, user: u, session_type: "agent_session", agent_type: "claude_code")
      s.save!(validate: false)
    end

    get company_project_analytics_path(@project)
    inertia_load_deferred_props("analytics")

    assert_inertia_props do |props|
      props[:activityHeatmap][:days].sum { |d| d[:count] } == 2
    end
  end

  test "participant_id narrows the heatmap and panels to one participant" do
    collaborator = create(:user, :employee, company: @company)
    create(:project_collaborator, project: @project, user: collaborator)
    [ @user, collaborator ].each do |u|
      s = build(:terminal_session, project: @project, user: u, session_type: "agent_session", agent_type: "claude_code")
      s.save!(validate: false)
    end

    get company_project_analytics_path(@project, participant_id: @user.id)
    inertia_load_deferred_props("analytics")

    assert_inertia_props do |props|
      props[:activityHeatmap][:days].sum { |d| d[:count] } == 1 &&
        props[:summary][:totalSessions] == 1
    end
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
