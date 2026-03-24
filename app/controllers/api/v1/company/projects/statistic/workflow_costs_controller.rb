# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Statistic
          class WorkflowCostsController < Projects::ApplicationController
            # GET /api/v1/company/projects/:project_id/statistic/workflow_costs
            #
            # Query params:
            #   scope  - user | project (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def show
              result = WorkflowCostAnalyticsService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: WorkflowCostAnalyticsSerializer.new(result).as_json
            end
          end
        end
      end
    end
  end
end
