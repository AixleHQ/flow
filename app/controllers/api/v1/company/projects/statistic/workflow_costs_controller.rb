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
            #   scope  - user | project | company (default: project)
            #   period - 7d | 30d | 90d | 1y     (default: 30d)
            def show
              result = WorkflowCostAnalyticsService.new(
                project: current_project,
                user: current_user,
                scope: params.fetch(:scope, "project"),
                period: params.fetch(:period, "30d")
              ).call

              render json: {
                workflows: result.workflows.map do |w|
                  {
                    workflowId: w.workflow_id,
                    workflowName: w.workflow_name,
                    totalCostCents: w.total_cost_cents,
                    inputTokens: w.input_tokens,
                    outputTokens: w.output_tokens,
                    totalTokens: w.total_tokens,
                    runCount: w.run_count
                  }
                end,
                timeSeries: result.time_series.map do |p|
                  {
                    date: p.date,
                    costCents: p.cost_cents,
                    totalTokens: p.total_tokens
                  }
                end,
                totals: {
                  totalCostCents: result.totals[:total_cost_cents],
                  inputTokens: result.totals[:input_tokens],
                  outputTokens: result.totals[:output_tokens],
                  totalTokens: result.totals[:total_tokens],
                  workflowCount: result.totals[:workflow_count],
                  avgCostCentsPerWorkflow: result.totals[:avg_cost_cents_per_workflow]
                }
              }
            end
          end
        end
      end
    end
  end
end
