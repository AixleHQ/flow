# frozen_string_literal: true

module PersonalTools
  class ListWorkflowRuns < Base
    tool do
      display_name "List Workflow Runs"
      description "List recent workflow runs in a project, newest first."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Filter to one workflow id."
      param :limit, type: :integer, description: "Max rows (default 25, cap 100)."
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)

      limit = [ (params[:limit].presence || 25).to_i, 100 ].min
      scope = WorkflowRun.where(project: project).order(created_at: :desc)
      scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?

      rows = scope.limit(limit).map do |run|
        { id: run.id, workflow_id: run.workflow_id, state: run.state,
          started_at: run.started_at, completed_at: run.completed_at, created_at: run.created_at }
      end
      success(project_id: project.id, runs: rows)
    end
  end
end
