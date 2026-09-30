# frozen_string_literal: true

module PersonalTools
  class GetWorkflowRun < Base
    tool do
      display_name "Get Workflow Run"
      description "Return a workflow run with the state of each of its step runs, and the files its steps " \
                  "wrote to /workspace/outputs (read one with read_asset, source run)."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :run_id, type: :integer, description: "Workflow run id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      run = WorkflowRun.where(project: project).includes(:workflow_run_assets, step_runs: :step)
                       .find_by(id: params[:run_id])
      return error("Run not found in this project") unless run

      step_runs = run.step_runs.sort_by { |sr| sr.step&.position.to_i }.map do |sr|
        { id: sr.id, step: sr.step&.name, state: sr.state,
          started_at: sr.started_at, completed_at: sr.completed_at }
      end
      success(id: run.id, workflow_id: run.workflow_id, state: run.state,
              started_at: run.started_at, completed_at: run.completed_at, step_runs: step_runs,
              outputs: outputs(run))
    end

    private

    def outputs(run)
      run.workflow_run_assets.sort_by(&:name).map do |asset|
        { id: asset.id, name: asset.name, size: asset.file_size, content_type: asset.content_type,
          step_run_id: asset.produced_by_step_run_id }
      end
    end
  end
end
