# frozen_string_literal: true

class Web::Company::Projects::WorkflowRunsController < Web::Company::Projects::ApplicationController
  # Runs and sessions are one list now — this route only exists so old links and
  # bookmarks land somewhere sensible.
  def index
    redirect_to company_project_sessions_path(current_project, type: "run")
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
    current_step = resolve_step_run(run)
    if current_step
      WorkflowService.approve_step(step_run: current_step)
    end
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  def retry_step
    run = current_project.workflow_runs.find(params[:id])
    step_run = resolve_step_run(run) || run.latest_failed_step_run

    if step_run&.retryable?
      result = WorkflowService.retry_step(step_run: step_run)
      # A retry on an already-closed run starts a brand-new run (result[:run]);
      # a live in-place retry stays on the same run.
      redirect_to company_project_workflow_run_path(current_project, result[:run] || run),
        alert: (result[:error] unless result[:ok])
    else
      redirect_to company_project_workflow_run_path(current_project, run)
    end
  end

  def skip_step
    run = current_project.workflow_runs.find(params[:id])
    current_step = resolve_step_run(run)
    if current_step
      WorkflowService.skip_step(step_run: current_step, reason: params[:reason])
    end
    redirect_to company_project_workflow_run_path(current_project, run)
  end

  private

  # A DAG run can have more than one step active at once, so the client names
  # which one it means. Falls back to the old single-"current step" behavior
  # for callers that don't pass it.
  def resolve_step_run(run)
    return run.step_runs.find(params[:step_run_id]) if params[:step_run_id].present?

    run.current_step_run
  end

  def workflow_run_params
    permitted = params.require(:workflow_run).permit(:workflow_id, :mode, :agent_runtime, :requested_model, input_asset_ids: [], repository_ids: [])
    permitted[:step_overrides] = normalized_step_overrides(params[:workflow_run][:step_overrides])
    permitted
  end

  # step_overrides is a free-form JSONB map {step_id => override}. Build an
  # explicit schema instead of passing to_unsafe_h through: keys must be integer
  # step IDs, and `auto_run` is the ONLY field the engine ever reads from an
  # override (workflow_run#step_auto_run?, WorkflowService#validate_mode!,
  # PrepareStepListActivity). Anything else is dropped so no unfiltered value
  # reaches the workflow engine (F16).
  def normalized_step_overrides(raw)
    return {} unless raw.respond_to?(:to_unsafe_h)

    raw.to_unsafe_h.each_with_object({}) do |(step_id, override), acc|
      next unless step_id.to_s.match?(/\A\d+\z/) && override.is_a?(Hash)

      clean = {}
      clean["auto_run"] = ActiveModel::Type::Boolean.new.cast(override["auto_run"]) if override.key?("auto_run")
      acc[step_id.to_s] = clean
    end
  end
end
