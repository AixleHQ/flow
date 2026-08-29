# frozen_string_literal: true

class Web::Company::Projects::OverviewController < Web::Company::Projects::ApplicationController
  def index
    summary = CompanyOverviewService.new(current_company, project: current_project).call
    workflow_run_stats = WorkflowRunStatsService.new(current_company, project: current_project).call
    board_distribution = BoardTaskDistributionService.new(current_company, project: current_project).call
    all_board_distribution = BoardTaskDistributionService.new(
      current_company, project: current_project, include_archived: true
    ).call
    recent = RecentActivityService.new(current_company, page: 1, per_page: 10, project: current_project).call

    render inertia: "Projects/Overview/OverviewPage", props: {
      project: project_props,
      summary: summary.to_h,
      workflow_run_stats: workflow_run_stats.to_h,
      board_task_distribution: board_distribution.to_h,
      all_board_task_distribution: all_board_distribution.to_h,
      recent_activity: recent[:activities].map { |a|
        {
          event_type: a[:event_type],
          description: a[:description],
          actor_name: a[:actor_name],
          occurred_at: a[:occurred_at]&.iso8601
        }
      }
    }
  end
end
