# frozen_string_literal: true

class Web::Company::Projects::AnalyticsController < Web::Company::Projects::ApplicationController
  def index
    scope = params.fetch(:scope, "project")
    period = params.fetch(:period, "30d")
    participant_id = params[:participant_id].presence
    filter_opts = {
      project: current_project, user: current_user, scope: scope, period: period,
      tags: params[:tags], task_type: params[:task_type], participant_id: participant_id
    }

    render inertia: "Projects/Analytics/AnalyticsPage", props: {
      project: project_props,
      scope: scope,
      period: period,
      participant_id: participant_id,
      participants: current_project.member_users.map { |u| { id: u.id, name: u.name, email: u.email } },
      activity_heatmap: InertiaRails.defer(group: "analytics") {
        heatmap_scope = current_project.terminal_sessions
        heatmap_scope = heatmap_scope.where(user_id: participant_id) if participant_id
        heatmap_scope = heatmap_scope.where(user_id: current_user.id) if scope == "user" && participant_id.blank?
        { days: ActivityHeatmapService.new(scope: heatmap_scope).call.map { |d| { date: d.date, count: d.count } } }
      },
      summary: InertiaRails.defer(group: "analytics") {
        result = ProjectAnalyticsService.new(**filter_opts).call
        {
          totalSessions: result.total_sessions,
          totalCostCents: result.total_cost_cents,
          totalTokens: result.total_tokens,
          avgCostCentsPerSession: result.avg_cost_cents_per_session,
          workflowsRun: result.workflows_run
        }
      },
      agent_activity: InertiaRails.defer(group: "analytics") {
        result = AgentActivityService.new(**filter_opts).call
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
        result = SessionSourceBreakdownService.new(**filter_opts).call
        { sources: result.sources.map { |s| { sessionType: s.session_type, label: s.label, count: s.count } } }
      },
      duration: InertiaRails.defer(group: "analytics") {
        result = SessionDurationDistributionService.new(**filter_opts).call
        { buckets: result.buckets.map { |b| { range: b.range, count: b.count } } }
      },
      cost_token: InertiaRails.defer(group: "analytics") {
        result = SessionCostTokenUsageService.new(**filter_opts).call
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
        result = WorkflowCostAnalyticsService.new(**filter_opts).call
        {
          workflows: result.workflows.map { |w|
            { workflowId: w.workflow_id, workflowName: w.workflow_name,
              totalCostCents: w.total_cost_cents, inputTokens: w.input_tokens,
              outputTokens: w.output_tokens, totalTokens: w.total_tokens,
              runCount: w.run_count, totalDurationSeconds: w.total_duration_seconds,
              avgDurationSeconds: w.avg_duration_seconds }
          },
          timeSeries: result.time_series.map { |p|
            { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens }
          },
          totals: {
            totalCostCents: result.totals[:total_cost_cents],
            inputTokens: result.totals[:input_tokens],
            outputTokens: result.totals[:output_tokens],
            totalTokens: result.totals[:total_tokens],
            workflowCount: result.totals[:workflow_count],
            avgCostCentsPerWorkflow: result.totals[:avg_cost_cents_per_workflow]
          }
        }
      }
    }
  end
end
