# frozen_string_literal: true

class Web::Company::Projects::WorkflowRunsController < Web::Company::Projects::ApplicationController
  def index
    scope = WorkflowRun.where(project: current_project)
                       .includes(:workflow, :step_runs)
                       .ransack(q_params)
                       .result
                       .order(created_at: :desc)

    render inertia: "Projects/WorkflowRuns/WorkflowRunsPage", props: {
      runs: inertia_scroll(scope) { |records|
        records.map { |r| WorkflowRunIndexResource.new(r).to_h }
      },
      filters: q_params,
      per_page: per_page
    }
  end

  def show
    run = WorkflowRun.where(project: current_project)
                     .includes(
                       step_runs: [ { sub_step_runs: :sub_step }, :step, :terminal_session ],
                       workflow: { steps: :sub_steps },
                       workflow_run_assets: { produced_by_step_run: :step }
                     )
                     .find(params[:id])

    render inertia: "Projects/WorkflowRuns/ShowPage", props: {
      project: project_props,
      run: WorkflowRunResource.new(run).to_h,
      assets: run.workflow_run_assets.map { |wra| WorkflowRunAssetResource.new(wra).to_h },
      cable_stream: inertia_cable_stream(run)
    }
  end

  def create
    workflow = Workflow.visible_for_project(current_project).find(workflow_run_params[:workflow_id])

    run = WorkflowService.start(
      workflow: workflow,
      project: current_project,
      user: current_user,
      mode: workflow_run_params[:mode]&.to_sym || :interactive,
      overrides: workflow_run_params[:step_overrides] || {},
      input_asset_ids: workflow_run_params[:input_asset_ids] || [],
      repository_ids: workflow_run_params[:repository_ids] || [],
      agent_runtime: workflow_run_params[:agent_runtime],
      requested_model: workflow_run_params[:requested_model]
    )

    if run.persisted?
      redirect_to company_project_workflow_run_path(current_project, run)
    else
      # WorkflowService.start returns an unsaved run when validation/start fails;
      # redirecting to its (nil-id) path raised UrlGenerationError
      # (Sentry PALAD-AI-RAILS-1W). Surface the errors and return to the launch page.
      redirect_back(
        fallback_location: company_project_workflow_runs_path(current_project),
        inertia: { errors: run.errors },
        alert: run.errors.full_messages.to_sentence.presence || "Could not start the workflow run."
      )
    end
  end

  def cancel
    run = current_project.workflow_runs.find(params[:id])
    WorkflowService.cancel(run: run)
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  def approve_step
    run = current_project.workflow_runs.find(params[:id])
    current_step = run.current_step_run
    if current_step
      WorkflowService.approve_step(step_run: current_step)
    end
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  def retry_step
    run = current_project.workflow_runs.find(params[:id])
    step_run = run.current_step_run || run.latest_failed_step_run
    if step_run&.retryable?
      WorkflowService.retry_step(step_run: step_run)
    end
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  def skip_step
    run = current_project.workflow_runs.find(params[:id])
    current_step = run.current_step_run
    if current_step
      WorkflowService.skip_step(step_run: current_step, reason: params[:reason])
    end
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  private

  def workflow_run_params
    permitted = params.require(:workflow_run).permit(:workflow_id, :mode, :agent_runtime, :requested_model, input_asset_ids: [], repository_ids: [])
    permitted[:step_overrides] = params[:workflow_run][:step_overrides]&.to_unsafe_h || {}
    permitted
  end
end
