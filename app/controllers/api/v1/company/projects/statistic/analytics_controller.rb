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
          end
        end
      end
    end
  end
end
