# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Statistic
          class AnalyticsController < Projects::ApplicationController
            # GET /api/v1/company/projects/:project_id/statistic/analytics
            #
            # Query params:
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def show
              result = ProjectAnalyticsService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                totalSessions: result.total_sessions,
                totalCostCents: result.total_cost_cents,
                totalTokens: result.total_tokens,
                avgCostCentsPerSession: result.avg_cost_cents_per_session,
                workflowsRun: result.workflows_run
              }
            end

            # GET /api/v1/company/projects/:project_id/statistic/analytics/agent_activity
            #
            # Query params:
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def agent_activity
              result = AgentActivityService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                agentTypes: result.agent_types,
                sessionsByAgent: result.sessions_by_agent.map do |a|
                  {
                    agentType: a.agent_type,
                    sessions: a.sessions,
                    costCents: a.cost_cents,
                    tokens: a.tokens
                  }
                end,
                activityOverTime: result.activity_over_time.map do |p|
                  {
                    date: p.date,
                    agentType: p.agent_type,
                    sessions: p.sessions
                  }
                end
              }
            end

            # GET /api/v1/company/projects/:project_id/statistic/analytics/session_source_breakdown
            #
            # Query params:
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def session_source_breakdown
              result = SessionSourceBreakdownService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                sources: result.sources.map do |s|
                  { sessionType: s.session_type, label: s.label, count: s.count }
                end
              }
            end

            # GET /api/v1/company/projects/:project_id/statistic/analytics/session_duration_distribution
            #
            # Query params:
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def session_duration_distribution
              result = SessionDurationDistributionService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                buckets: result.buckets.map do |b|
                  { range: b.range, count: b.count }
                end
              }
            end

            # GET /api/v1/company/projects/:project_id/statistic/analytics/cost_token_usage
            #
            # Query params:
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def cost_token_usage
              result = SessionCostTokenUsageService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                timeSeries: result.time_series.map do |p|
                  { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens }
                end,
                totals: {
                  totalCostCents: result.totals.total_cost_cents,
                  totalTokens: result.totals.total_tokens,
                  avgCostCentsPerSession: result.totals.avg_cost_cents_per_session
                }
              }
            end
          end
        end
      end
    end
  end
end
