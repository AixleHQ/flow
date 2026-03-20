# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class AnalyticsController < ApplicationController
          # GET /api/v1/company/projects/:project_id/analytics
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
        end
      end
    end
  end
end
