# frozen_string_literal: true

class Web::Company::AnalyticsController < Web::Company::ApplicationController
  def index
    scope = params.fetch(:scope, "company")
    period = params.fetch(:period, "30d")
    filter_opts = { company: current_company, user: current_user, scope: scope, period: period }

    render inertia: "Company/Analytics/AnalyticsPage", props: {
      scope: scope,
      period: period,
      summary: InertiaRails.defer(group: "analytics") {
        result = CompanyAnalyticsService.new(**filter_opts).call
        {
          totalSessions: result.total_sessions,
          totalCostCents: result.total_cost_cents,
          totalTokens: result.total_tokens,
          avgCostCentsPerSession: result.avg_cost_cents_per_session,
          workflowsRun: result.workflows_run,
          projectBreakdowns: result.project_breakdowns.map { |p|
            {
              projectId: p.project_id,
              projectName: p.project_name,
              sessions: p.sessions,
              costCents: p.cost_cents,
              tokens: p.tokens
            }
          }
        }
      },
      agent_activity: InertiaRails.defer(group: "analytics") {
        result = CompanyAgentActivityService.new(**filter_opts).call
        {
          agentTypes: result.agent_types,
          sessionsByAgent: result.sessions_by_agent.map { |a|
            { agentType: a.agent_type, sessions: a.sessions, costCents: a.cost_cents, tokens: a.tokens }
          },
          activityOverTime: result.activity_over_time.map { |p|
            { date: p.date, agentType: p.agent_type, sessions: p.sessions }
          }
        }
      },
      sources: InertiaRails.defer(group: "analytics") {
        result = CompanySessionSourceBreakdownService.new(**filter_opts).call
        { sources: result.sources.map { |s| { sessionType: s.session_type, label: s.label, count: s.count } } }
      },
      cost_token: InertiaRails.defer(group: "analytics") {
        result = CompanySessionCostTokenUsageService.new(**filter_opts).call
        {
          timeSeries: result.time_series.map { |p| { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens } },
          totals: {
            totalCostCents: result.totals.total_cost_cents,
            totalTokens: result.totals.total_tokens,
            avgCostCentsPerSession: result.totals.avg_cost_cents_per_session
          }
        }
      },
      workflow_costs: InertiaRails.defer(group: "analytics") {
        result = CompanyWorkflowCostAnalyticsService.new(**filter_opts).call
        { timeSeries: result.time_series.map { |p| { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens } } }
      }
    }
  end
end
